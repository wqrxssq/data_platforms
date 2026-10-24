#!/usr/bin/env python3
"""Тестовые продажи в CSV: python3 gen_sales.py [строк] [первый день] [дней]"""
import csv
import random
import sys
from datetime import date, timedelta

rows = int(sys.argv[1]) if len(sys.argv) > 1 else 10000
start = date.fromisoformat(sys.argv[2]) if len(sys.argv) > 2 else date(2025, 10, 1)
days = int(sys.argv[3]) if len(sys.argv) > 3 else 14

regions = ["Moscow", "Saint Petersburg", "Kazan", "Novosibirsk", "Yekaterinburg"]
products = {"laptop": 899.0, "phone": 499.0, "tablet": 329.0, "monitor": 199.0,
            "keyboard": 49.0, "mouse": 19.0, "headphones": 89.0}
rng = random.Random(23)
out = csv.writer(sys.stdout, lineterminator="\n")
out.writerow(["order_id", "order_date", "customer_id", "region", "product", "quantity", "price"])
for order_id in range(1, rows + 1):
    product = rng.choice(list(products))
    price = round(products[product] * rng.uniform(0.9, 1.1), 2)
    out.writerow([order_id, start + timedelta(days=rng.randrange(days)), rng.randint(1, 2000),
                  rng.choice(regions), product, rng.randint(1, 5), f"{price:.2f}"])
