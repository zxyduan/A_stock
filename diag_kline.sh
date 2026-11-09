#!/bin/sh
set +e
echo "== host cache dir =="
ls -la /data/instock/app/cache/
echo "== done/failed/progress =="
wc -l /data/instock/app/cache/kline_done.txt 2>/dev/null || echo no-done
cat /data/instock/app/cache/kline_failed.txt 2>/dev/null | head -5 || true
echo "== foreground smoke: 3 codes since 2021 =="
docker exec InStock sh -c 'cd /data/InStock && PYTHONPATH=/data/InStock KLINE_LIMIT=3 KLINE_START=20210101 KLINE_WORKERS=2 python3 instock/cache/kline_history_loader.py'
echo "== rows after smoke =="
docker exec InStockDbService mariadb -uroot -proot instockdb -e "SELECT COUNT(*) rows_now, COUNT(DISTINCT code) codes_now FROM cn_stock_daily_kline;"
echo DIAG_DONE
