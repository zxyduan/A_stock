#!/bin/sh
# 历史入库小批量验证: 20只, 2024年以来
set +e
echo "== run 20-code probe =="
docker exec InStock sh -c 'cd /data/InStock && KLINE_LIMIT=20 KLINE_START=20240101 PYTHONPATH=/data/InStock python3 instock/cache/kline_history_loader.py'
echo "== table summary =="
docker exec InStockDbService mariadb -uroot -proot instockdb -e "SELECT COUNT(*) AS rows_cnt, COUNT(DISTINCT code) AS codes, MIN(date) AS min_date, MAX(date) AS max_date FROM cn_stock_daily_kline;"
echo "== sample 600519 latest =="
docker exec InStockDbService mariadb -uroot -proot instockdb -e "SELECT code,name,date,open,close,volume,p_change FROM cn_stock_daily_kline WHERE code='600519' ORDER BY date DESC LIMIT 3;"
echo PROBE_DONE
