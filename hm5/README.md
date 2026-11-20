# Prefect

Продолжение [ДЗ 4](../hm4/README.md): обработка продаж через поток Prefect

Spark работает на YARN, читает CSV из HDFS и сохраняет результат в таблицу `hm5.sales`

## Запуск

Команды выполняются на edge (`team-23-en`) от `team`, нужны sudo без пароля и работающие HDFS, YARN и Hive из прошлых ДЗ

Spark уже установлен в `/opt/spark`, входной файл — `/user/hive/staging/sales/sales.csv` без заголовка

Из каталога репозитория:

```bash
cd hm5
./scripts/setup.sh    # Python-окружение и Prefect
./scripts/start.sh    # запуск потока
./scripts/check.sh    # повторная проверка таблицы
```

`setup.sh` при необходимости устанавливает `python3-venv`, затем Prefect 3.9.4 в `.venv`

Prefect запускает временный локальный сервер автоматически, подключение к облаку не требуется

## Обработка

В `flow.py` четыре последовательных шага:

1. Проверить CSV в HDFS и посчитать исходные заказы и выручку
2. Запустить `spark/job.py` через `spark-submit --master yarn`
3. Создать внешнюю таблицу Hive поверх результата
4. Сверить число заказов и выручку в таблице с исходным CSV

Spark приводит дату, количество и цену к нужным типам, группирует продажи по дню и региону, считает `orders_count` и `total_revenue`

Parquet записывается в `/user/hive/warehouse/hm5.db/sales` с партициями по `order_date`

Память driver и каждого executor — по 512 МБ

Повторный запуск перезаписывает только результат ДЗ 5, входной CSV и таблицы прошлых работ остаются на месте

## Проверка

Успешный запуск заканчивается состоянием `Completed` в Prefect и строкой `Проверка пройдена`

Приложение `hm5_sales` в YARN должно завершиться с `SUCCEEDED`

Логи Spark, YARN, Hive и результат сверки сохраняются в `evidence/`

Проверено на стенде 20 ноября: поток завершился с `Completed`, приложение YARN — с `SUCCEEDED`, в результате 10 000 заказов

Посмотреть таблицу вручную:

```bash
/opt/hive/bin/beeline -u jdbc:hive2://team-23-en:10000/default -n hive
```

```sql
SHOW PARTITIONS hm5.sales;
SELECT * FROM hm5.sales ORDER BY order_date, region LIMIT 10;
SELECT SUM(orders_count), SUM(total_revenue) FROM hm5.sales;
```

Службы прошлых ДЗ останавливать не нужно, поток завершается сам
