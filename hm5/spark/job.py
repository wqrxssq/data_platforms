from pyspark.sql import SparkSession
from pyspark.sql.functions import col, count, sum as spark_sum

spark = SparkSession.builder.appName('hm5_sales').getOrCreate()

try:
    columns = ['order_id', 'order_date', 'customer_id', 'region', 'product', 'quantity', 'price']
    df = spark.read.option('mode', 'FAILFAST').csv('/user/hive/staging/sales/sales.csv').toDF(*columns)
    df = (df.withColumn('order_date', col('order_date').cast('date'))
            .withColumn('quantity', col('quantity').cast('int'))
            .withColumn('price', col('price').cast('decimal(12,2)')))
    if df.filter('order_date IS NULL OR region IS NULL OR quantity IS NULL OR price IS NULL').limit(1).count():
        raise ValueError('В CSV есть пустые или некорректные значения')

    result = df.groupBy('order_date', 'region').agg(
        count('*').alias('orders_count'),
        spark_sum(col('quantity') * col('price')).cast('decimal(22,2)').alias('total_revenue'),
    )
    result.write.mode('overwrite').partitionBy('order_date').parquet('/user/hive/warehouse/hm5.db/sales')
finally:
    spark.stop()
