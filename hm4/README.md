# Spark

Продолжение [ДЗ 1](../hm1/README.md), [ДЗ 2](../hm2/README.md) и [ДЗ 3](../hm3/README.md): Apache Spark под управлением YARN для чтения, трансформации и записи данных.

Новых служб нет: Spark ставится на edge и работает только во время задачи, всё выполнение на YARN. Данные лежат в HDFS из ДЗ 1, таблица регистрируется в Hive из ДЗ 3

| Узел   | Что появилось                                   |
| ---------- | ----------------------------------------------------------- |
| team-23-en | Spark 3.5.9 в `/opt/spark`                               |
| team-23-nn | архив jar в HDFS `/apps/spark/spark-3.5.9-jars.zip` |

Задача запускается от `hdfs`: ему доступны и staging, и warehouse

## Запуск

Команды выполняются на edge (`team-23-en`) от `team`, нужны sudo без пароля, как в прошлых работах

Перед запуском должны работать HDFS, YARN и HiveServer2, для проверки из каталога репозитория необходимо выполнить

```bash
cd hm4
sudo -u hdfs -H /opt/hadoop/bin/hdfs dfsadmin -safemode get
sudo -u hdfs -H /opt/hadoop/bin/yarn node -list
```

Ожидается `Safe mode is OFF` и три NodeManager в `RUNNING`

```bash
./scripts/setup.sh
./scripts/load.sh
./scripts/start.sh
./scripts/check.sh
```

Скрипты можно запускать повторно: скачанное пропускается, данные перезаливаются, задача перезаписывает результат

## Что делает setup.sh

1. Скачивает `spark-3.5.9-bin-hadoop3.tgz` с [https://archive.apache.org/dist/spark/spark-3.5.9/](https://archive.apache.org/dist/spark/spark-3.5.9/) в `/var/tmp`, распаковывает в `/opt/spark`, копирует туда `conf/`
2. Пакует jar из `/opt/spark/jars `в один архив в HDFS. `zip` на стенде нет, архив делает утилита `jar` из JDK

## Настройки

`conf/spark-defaults.conf`:

```bash
spark.master                     yarn
spark.submit.deployMode          client
spark.driver.memory              1g
spark.yarn.am.memory             512m
spark.executor.instances         2
spark.executor.cores             1
spark.executor.memory            1g
spark.sql.shuffle.partitions     8
spark.sql.warehouse.dir          hdfs://team-23-nn:9000/user/hive/warehouse
spark.yarn.archive               hdfs://team-23-nn:9000/apps/spark/spark-3.5.9-jars.zip
spark.ui.showConsoleProgress     true
```

`conf/spark-env.sh`:

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop
export PYSPARK_PYTHON=python3
```

## Что делает start.sh

1. Копирует `spark/job.py` в `/tmp` и запускает через `spark-submit` от `hdfs`: домашняя папка `team` ему не видна
2. Читает `/user/hive/staging/sales/sales.csv`, приводит данные к нужным типам, группирует по дню и региону  число заказов и `SUM(quantity × price)`, пишет parquet в warehouse с папкой для каждого отдельного дня (`partitionBy("order_date")`)
3. Проверяет статус приложения в YARN, дальше идёт только при `SUCCEEDED`
4. Через beeline выполняет `sql/create.hql`: внешняя таблица `hm4.sales_agg` поверх записанных файлов, `MSCK REPAIR TABLE` собирает партиции по папкам

## Загрузка данных

`./scripts/load.sh` без аргументов генерирует 10 000 продаж за 14 дней (`gen_sales.py `тот же, что в ДЗ 3). CSV без заголовка кладётся в `/user/hive/staging/sales`

## Проверка

`check.sh`:

- проверяет партиции в HDFS:  считает число папок, результат должен совпасть с `SHOW PARTITIONS`
- показывает `SHOW PARTITIONS`, `SELECT * ... LIMIT 10`, проверка`SUM(orders_count) = 10000`

В конце ожидается `Проверка пройдена`. Логи сохраняются в `evidence/`.

## Веб-интерфейсы

С ноутбука:

```bash
ssh -N -L 127.0.0.1:8088:team-23-nn:8088 -L 127.0.0.1:9870:team-23-nn:9870 -i ~/.ssh/mts_course_ed25519 team@111.88.130.82
```

Затем открыть [localhost:8088](http://localhost:8088/) - YARN (там `hm4_sales_agg` со статусом `SUCCEEDED`), [localhost:9870](http://localhost:9870/) - HDFS (можно найти папки `order_date=...`). `Ctrl+C` закрывает подключение.

Spark живёт только пока идёт задача (во время start.sh) - [team-23-en:4040](http://team-23-en:4040/)

## Остановка

Останавливать нечего : задача завершается сама, службы прошлых работ не трогаются

## Порты

| Порт | Узел   | Назначение                                |
| -------- | ---------- | --------------------------------------------------- |
| 8088     | team-23-nn | веб-интерфейс ResourceManager           |
| 9870     | team-23-nn | веб-интерфейс NameNode                  |
| 4040     | team-23-en | Spark UI, только во время задачи |
| 10000    | team-23-en | HiveServer2                                         |
