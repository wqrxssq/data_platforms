import argparse
import csv
import io
import re
import subprocess
from datetime import datetime
from decimal import Decimal
from pathlib import Path
from tempfile import TemporaryDirectory

from prefect import flow, task
from prefect.cache_policies import NO_CACHE

ROOT = Path(__file__).resolve().parent
INPUT = '/user/hive/staging/sales/sales.csv'
HDFS = ['sudo', '-n', '-u', 'hdfs', '-H', '/opt/hadoop/bin/hdfs']
HIVE = ['/opt/hive/bin/beeline', '-u', 'jdbc:hive2://team-23-en:10000/default',
        '-n', 'hive', '--silent=true', '--showHeader=false', '--outputformat=tsv2']


def run(command, log=None):
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if log:
        log.write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f'Команда завершилась с ошибкой: {command[0]}, лог: {log}')
    return result.stdout + (result.stderr if log else '')


@task(cache_policy=NO_CACHE)
def check_input():
    run(HDFS + ['dfs', '-test', '-s', INPUT])
    text = run(HDFS + ['dfs', '-cat', INPUT])
    rows = list(csv.reader(io.StringIO(text)))
    if not rows or any(len(row) != 7 for row in rows):
        raise ValueError('Ожидается непустой CSV из ДЗ 4 без заголовка, 7 колонок')
    revenue = sum((Decimal(row[5]) * Decimal(row[6]) for row in rows), Decimal(0))
    return len(rows), revenue


@task(cache_policy=NO_CACHE)
def process_sales(logs):
    # hdfs не может читать домашний каталог team
    with TemporaryDirectory(prefix='hm5-', dir='/tmp') as folder:
        stage = Path(folder)
        stage.chmod(0o755)
        job = stage / 'job.py'
        job.write_bytes((ROOT / 'spark/job.py').read_bytes())
        job.chmod(0o644)
        output = run(['sudo', '-n', '-u', 'hdfs', '-H', '/opt/spark/bin/spark-submit',
                      '--master', 'yarn', '--deploy-mode', 'client',
                      '--driver-memory', '512m', '--executor-memory', '512m', str(job)], logs / 'spark.log')
    match = re.search(r'application_\d+_\d+', output)
    if not match:
        raise RuntimeError('В логе Spark нет ID приложения YARN')
    app = match.group()
    status = run(['sudo', '-n', '-u', 'hdfs', '-H', '/opt/hadoop/bin/yarn',
                  'application', '-status', app], logs / 'yarn.log')
    if not re.search(r'\bState\s*:\s*FINISHED\b', status) or not re.search(r'Final-State\s*:\s*SUCCEEDED\b', status):
        raise RuntimeError(f'Приложение {app} не завершилось успешно')
    print(f'YARN: {app} SUCCEEDED')


@task(cache_policy=NO_CACHE)
def register_table(logs):
    run(HIVE + ['-f', str(ROOT / 'sql/create.hql')], logs / 'hive.log')


@task(cache_policy=NO_CACHE)
def check_table(expected, logs):
    output = run(HIVE + ['-e', 'SELECT SUM(orders_count), SUM(total_revenue) FROM hm5.sales;'])
    (logs / 'check.tsv').write_text(output)
    fields = output.strip().split('\t')
    if len(fields) != 2 or int(fields[0]) != expected[0] or Decimal(fields[1]) != expected[1]:
        raise ValueError(f'Итоги таблицы не совпали с CSV: {output.strip()}, ожидалось {expected}')
    print(f'Проверка пройдена: {fields[0]} заказов, выручка {fields[1]}')


@flow(name='hm5_sales', log_prints=True)
def sales(check_only=False):
    logs = ROOT / 'evidence' / datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    logs.mkdir(parents=True)
    expected = check_input()
    if not check_only:
        process_sales(logs)
        register_table(logs)
    check_table(expected, logs)
    print(f'Логи: {logs}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    sales(check_only=parser.parse_args().check)
