#!/bin/sh
# 全量历史日线后台启动(断点续跑; 已完成代码在 kline_done.txt 自动跳过)
set +e
docker exec -d InStock sh -c 'cd /data/InStock && PYTHONPATH=/data/InStock KLINE_START=20210101 KLINE_WORKERS=6 python3 instock/cache/kline_history_loader.py >> instock/cache/kline_history.log 2>&1'
sleep 8
echo "== loader process =="
docker exec InStock sh -c "ps aux | grep kline_history_loader | grep -v grep || echo NOT_RUNNING"
echo "== log tail =="
docker exec InStock sh -c "tail -n 20 instock/cache/kline_history.log 2>/dev/null || echo no-log-yet"
echo "== current rows =="
docker exec InStockDbService mariadb -uroot -proot instockdb -e "SELECT COUNT(*) rows_now, COUNT(DISTINCT code) codes_now FROM cn_stock_daily_kline;"
echo START_FULL_DONE
