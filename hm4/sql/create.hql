CREATE DATABASE IF NOT EXISTS hm4;
USE hm4;

DROP TABLE IF EXISTS sales_agg;

CREATE EXTERNAL TABLE sales_agg (
  region STRING,
  orders_count BIGINT,
  total_revenue DOUBLE
)
PARTITIONED BY (order_date DATE)
STORED AS PARQUET
LOCATION '/user/hive/warehouse/hm4.db/sales_agg';

MSCK REPAIR TABLE sales_agg;
