#!/bin/sh
set +e
echo "== cron service =="; systemctl is-active cron 2>/dev/null || true
echo "== loader proc =="; docker top InStock | grep kline_history_loader || echo none
echo "== loader log tail =="; tail -n 8 /data/instock/app/cache/kline_history.log
echo "== progress tail =="; tail -n 5 /data/instock/app/cache/kline_progress.txt
echo "== table rows =="
docker exec InStockDbService mariadb -uroot -proot instockdb -e "SELECT COUNT(*) rows_now, COUNT(DISTINCT code) codes_now, MIN(date) mn, MAX(date) mx FROM cn_stock_daily_kline;"
echo "== done/failed counts =="
wc -l /data/instock/app/cache/kline_done.txt 2>/dev/null
wc -l /data/instock/app/cache/kline_failed.txt 2>/dev/null || echo "0 failed"
echo "== web still 200 =="; curl -sS -m5 -o /dev/null -w "web=%{http_code}\n" http://127.0.0.1:9988/instock/
echo STATUS_DONE
