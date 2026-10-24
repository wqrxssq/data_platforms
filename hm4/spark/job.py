#!/usr/bin/env python3
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, count, sum as _sum
from pyspark.sql.types import DateType, DoubleType, IntegerType

spark = SparkSession.builder \
    .appName("hm4_sales_agg") \
    .getOrCreate()

# csv заливается без заголовка, поэтому имена колонок задаём сами
columns = ["order_id", "order_date", "customer_id", "region", "product", "quantity", "price"]
df = spark.read.csv("/user/hive/staging/sales/sales.csv").toDF(*columns)

# данные приходят строками, приводим к нужным типам
df = df \
    .withColumn("order_date", col("order_date").cast(DateType())) \
    .withColumn("quantity", col("quantity").cast(IntegerType())) \
    .withColumn("price", col("price").cast(DoubleType()))

# по каждому дню и региону считаем число заказов и выручку
agg = df.groupBy("order_date", "region") \
    .agg(
        count("*").alias("orders_count"),
        _sum(col("quantity") * col("price")).alias("total_revenue")
    )

# пишем партициями по дате, таблицу на это повесит Hive
agg.write.mode("overwrite").partitionBy("order_date").parquet("/user/hive/warehouse/hm4.db/sales_agg")

spark.stop()
