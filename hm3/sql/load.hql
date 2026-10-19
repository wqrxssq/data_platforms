CREATE DATABASE IF NOT EXISTS hm3;
USE hm3;

-- Сырые CSV в HDFS без строки заголовка, таблица только описывает их
DROP TABLE IF EXISTS sales_staging;
CREATE EXTERNAL TABLE sales_staging (
  order_id BIGINT,
  order_date STRING,
  customer_id INT,
  region STRING,
  product STRING,
  quantity INT,
  price DECIMAL(10,2)
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '${staging_dir}';

-- Итоговая таблица, по партиции на каждый день
CREATE TABLE IF NOT EXISTS sales (
  order_id BIGINT,
  customer_id INT,
  region STRING,
  product STRING,
  quantity INT,
  price DECIMAL(10,2)
)
PARTITIONED BY (order_date DATE)
STORED AS ORC;

SET hive.exec.dynamic.partition = true;
SET hive.exec.dynamic.partition.mode = nonstrict;

-- Перезаписываются только дни, которые есть в новой выгрузке
INSERT OVERWRITE TABLE sales PARTITION (order_date)
SELECT order_id, customer_id, region, product, quantity, price, CAST(order_date AS DATE)
FROM sales_staging;

SHOW PARTITIONS sales;
