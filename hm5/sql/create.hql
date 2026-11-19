CREATE DATABASE IF NOT EXISTS hm5;
DROP TABLE IF EXISTS hm5.sales;
CREATE EXTERNAL TABLE hm5.sales (
  region STRING,
  orders_count BIGINT,
  total_revenue DECIMAL(22,2)
)
PARTITIONED BY (order_date DATE)
STORED AS PARQUET
LOCATION '/user/hive/warehouse/hm5.db/sales';
MSCK REPAIR TABLE hm5.sales;
