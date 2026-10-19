# Hive

Продолжение [ДЗ 1](../hm1/README.md) и [ДЗ 2](../hm2/README.md): Apache Hive 4.0.0-alpha-2 и загрузка данных в партиционированную таблицу

Hive развёрнут не в embedded-режиме: метаданные хранятся в PostgreSQL, Metastore работает отдельной службой, а клиенты подключаются к HiveServer2 по JDBC. Поэтому с Hive одновременно могут работать несколько клиентов с разных узлов

| Узел | Новые службы |
|---|---|
| team-23-nn | PostgreSQL (база `metastore`), Hive Metastore |
| team-23-en | HiveServer2, клиент beeline |

Запросы выполняются на YARN из ДЗ 2 (движок MapReduce), таблицы хранятся в HDFS в `/user/hive/warehouse`

Службы Hive работают от системного пользователя `hive` и запускаются через systemd (`hive-metastore`, `hiveserver2`)

## Запуск

Команды выполняются на edge (`team-23-en`) от `team`. Нужны sudo без пароля и SSH-ключ `~/.ssh/team_internal` для `team-23-nn`, как в ДЗ 2

Перед установкой должны работать HDFS и YARN:

```bash
cd hm3
sudo -u hdfs -H /opt/hadoop/bin/hdfs dfsadmin -safemode get
sudo -u hdfs -H /opt/hadoop/bin/yarn node -list
```

Ожидается `Safe mode is OFF` и три NodeManager в `RUNNING`

```bash
./scripts/setup.sh    # установка Hive, PostgreSQL, схема Metastore, каталоги в HDFS
./scripts/start.sh    # запуск Metastore и HiveServer2
./scripts/load.sh     # загрузка данных в партиционированную таблицу
./scripts/check.sh    # проверка
```

Скрипты можно запускать повторно: уже установленное и созданное пропускается, `setup.sh` перезапускает работающие службы с новыми настройками

## Что делает setup.sh

Те же шаги можно выполнить вручную

1. Скачивает `apache-hive-4.0.0-alpha-2-bin.tar.gz` с <https://archive.apache.org/dist/hive/hive-4.0.0-alpha-2/> и JDBC-драйвер PostgreSQL 42.7.4 из Maven Central в `/var/tmp` на edge, сверяет SHA-256

2. На `team-23-en` и `team-23-nn` ([scripts/node/install-hive.sh](scripts/node/install-hive.sh)):

   ```bash
   sudo useradd --system --create-home --home-dir /var/lib/hive --shell /bin/bash --user-group hive
   sudo tar -C /opt --no-same-owner -xzf apache-hive-4.0.0-alpha-2-bin.tar.gz
   sudo ln -sfn /opt/apache-hive-4.0.0-alpha-2-bin /opt/hive
   sudo cp postgresql-42.7.4.jar /opt/hive/lib/
   sudo cp conf/hive-site.xml conf/hive-env.sh /opt/hive/conf/
   sudo cp conf/hive.sh /etc/profile.d/hive.sh
   sudo install -d -o hive -g hive /var/lib/hive /var/log/hive
   ```

3. Каталоги в HDFS:

   ```bash
   sudo -u hdfs -H hdfs dfs -mkdir -p /user/hive/warehouse /tmp/hive /tmp/hadoop-yarn/staging
   sudo -u hdfs -H hdfs dfs -chown -R hive:hive /user/hive
   sudo -u hdfs -H hdfs dfs -chmod 1777 /tmp /tmp/hive /tmp/hadoop-yarn/staging
   ```

   Без прав на `/tmp/hadoop-yarn/staging` задачи MapReduce от пользователя `hive` не запустятся: каталог создал `hdfs` при проверке ДЗ 2

4. На `team-23-nn` ([scripts/node/setup-metastore.sh](scripts/node/setup-metastore.sh)):

   ```bash
   sudo apt-get install -y postgresql
   sudo -u postgres psql
   ```

   ```sql
   CREATE ROLE hive LOGIN PASSWORD '...';
   CREATE DATABASE metastore OWNER hive;
   ```

   Пароль генерируется при первом запуске и лежит в `/etc/hive/metastore-db.password` (права `640 root:hive`), в репозиторий он не попадает. PostgreSQL слушает только localhost: к базе обращается только Metastore на этом же узле

   Настройки подключения к базе — в `/opt/hive/conf/hivemetastore-site.xml` ([шаблон](conf/hivemetastore-site.xml)), этот файл читает только Metastore. Затем создаётся схема:

   ```bash
   sudo -u hive -H /opt/hive/bin/schematool -dbType postgres -initSchema
   sudo -u hive -H /opt/hive/bin/schematool -dbType postgres -info
   ```

   Ожидается `Metastore schema version: 4.0.0-alpha-2`

5. Юниты [hive-metastore.service](conf/hive-metastore.service) на `team-23-nn` и [hiveserver2.service](conf/hiveserver2.service) на `team-23-en` копируются в `/etc/systemd/system` и включаются через `systemctl enable`, поэтому после перезагрузки ВМ Hive стартует сам

## Настройки

[conf/hive-site.xml](conf/hive-site.xml) одинаковый на обоих узлах:

| Параметр | Значение |
|---|---|
| `hive.metastore.uris` | `thrift://team-23-nn:9083` — клиенты и HiveServer2 ходят в общий Metastore |
| `hive.metastore.warehouse.dir` | `/user/hive/warehouse` |
| `hive.server2.thrift.bind.host`, `port` | `team-23-en:10000` |
| `hive.server2.enable.doAs` | `false`, запросы выполняются от `hive` |
| `hive.execution.engine` | `mr` |

Память: Metastore — 512 МБ, HiveServer2 — 1 ГБ, клиенты — 256 МБ ([conf/hive-env.sh](conf/hive-env.sh)). Контейнеры задач — по 512 МБ, как в ДЗ 2

### Java 17

Hadoop на стенде работает на Java 17, а Hive 4.0.0-alpha-2 рассчитан на Java 8. Без доработок HiveServer2 не стартует, а задачи падают с `InaccessibleObjectException`. Поэтому:

- в `hive-env.sh` к JVM служб и клиентов добавлены `--add-opens` для нужных пакетов JDK
- в `hive-site.xml` те же флаги добавлены в `mapreduce.map.java.opts`, `mapreduce.reduce.java.opts` и `yarn.app.mapreduce.am.command-opts` — только для задач, запущенных из Hive
- в Hadoop 3.4 нет `commons-collections` 3.x, он передаётся задачам через `hive.aux.jars.path`
- `hive.exec.submit.local.task.via.child=false`: хеш-таблицы для map join строятся внутри HiveServer2, отдельная JVM для этого не стартует. В map join попадают только таблицы меньше 10 МБ

Настройки Hadoop из ДЗ 1 и ДЗ 2 не меняются

## Загрузка данных

`./scripts/load.sh` без аргументов генерирует 10 000 тестовых продаж за 14 дней ([scripts/gen_sales.py](scripts/gen_sales.py)). Можно передать свой CSV с тем же заголовком:

```
order_id,order_date,customer_id,region,product,quantity,price
```

```bash
./scripts/load.sh /path/to/sales.csv
```

Шаги ([sql/load.hql](sql/load.hql)):

1. CSV без строки заголовка кладётся в HDFS в `/user/hive/staging/sales`. Заголовок отрезается до загрузки: `skip.header.line.count` в этой версии Hive не срабатывает при чтении через MapReduce
2. Внешняя таблица `hm3.sales_staging` описывает этот каталог
3. `hm3.sales` в формате ORC партиционирована по `order_date`
4. Динамическое партиционирование раскладывает строки по дням:

   ```sql
   SET hive.exec.dynamic.partition.mode = nonstrict;
   INSERT OVERWRITE TABLE sales PARTITION (order_date)
   SELECT order_id, customer_id, region, product, quantity, price, CAST(order_date AS DATE)
   FROM sales_staging;
   ```

`INSERT OVERWRITE` с динамическими партициями перезаписывает только дни из нового файла, остальные партиции остаются. Поэтому повторная загрузка того же файла не дублирует данные, а новый файл дописывает новые дни

Hive 4 сам переводит такую managed-таблицу в external с `external.table.purge=true`: данные лежат в `/user/hive/warehouse/hm3.db/sales/order_date=YYYY-MM-DD` и удаляются вместе с таблицей

## Проверка

`check.sh`:

- проверяет, что `hive-metastore`, `postgresql` и `hiveserver2` активны и слушают порты
- выводит таблицы `hm3` и число партиций прямо из базы `metastore` в PostgreSQL
- одновременно запускает два клиента beeline — на `team-23-en` и на `team-23-nn`. Первый считает строки по партициям `hm3.sales`, второй — по дням в исходном CSV, результаты должны совпасть
- сверяет число каталогов партиций в HDFS и делает `fsck`

В конце ожидается `Проверка пройдена`. Логи и результаты сохраняются в `evidence/`

## Подключение клиентов

С `team-23-en` или `team-23-nn`, сколько угодно сессий одновременно:

```bash
/opt/hive/bin/beeline -u jdbc:hive2://team-23-en:10000/default -n "$USER"
```

```sql
SHOW PARTITIONS hm3.sales;
SELECT order_date, COUNT(*), SUM(quantity * price) FROM hm3.sales GROUP BY order_date;
```

Веб-интерфейс HiveServer2 со списком сессий и запросов — на `team-23-en:10002`. С ноутбука через SSH-туннель:

```bash
ssh -N -L 127.0.0.1:10002:team-23-en:10002 -i ~/.ssh/mts_course_ed25519 team@111.88.130.82
```

Затем открыть [localhost:10002](http://localhost:10002/)

## Остановка

```bash
./scripts/stop.sh
```

Останавливаются HiveServer2 и Metastore. PostgreSQL, HDFS и YARN продолжают работать, данные и метаданные сохраняются

Повторный запуск — `./scripts/start.sh`

## Порты и логи

| Порт | Узел | Назначение |
|---|---|---|
| 5432 | team-23-nn, только localhost | PostgreSQL |
| 9083 | team-23-nn | Hive Metastore (Thrift) |
| 10000 | team-23-en | HiveServer2 (JDBC) |
| 10002 | team-23-en | веб-интерфейс HiveServer2 |

Логи: `/var/log/hive/metastore.log`, `/var/log/hive/hiveserver2.log`, `journalctl -u hive-metastore -u hiveserver2`
