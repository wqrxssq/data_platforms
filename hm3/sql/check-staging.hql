SELECT CAST(order_date AS DATE) AS order_date, COUNT(*)
FROM hm3.sales_staging
GROUP BY CAST(order_date AS DATE)
ORDER BY order_date;
