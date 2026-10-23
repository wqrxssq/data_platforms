SELECT order_date, COUNT(*)
FROM hm3.sales
WHERE order_date IN (SELECT DISTINCT CAST(order_date AS DATE) FROM hm3.sales_staging)
GROUP BY order_date
ORDER BY order_date;
