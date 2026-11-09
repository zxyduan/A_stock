#!/bin/sh
echo "== free =="; free -h
echo "== swapon =="; swapon --show 2>/dev/null || echo "no swap"
echo "== disk / =="; df -h /
echo "== backup dir =="; ls -la /data/instock/backup 2>/dev/null || echo "no backup dir"
echo "== host crontab =="; crontab -l 2>/dev/null || echo "no host crontab"
echo "== docker system df =="; docker system df
echo "== app cache dir =="; ls -la /data/instock/app/cache 2>/dev/null || echo "no cache dir"
echo "== containers =="; cd /data/instock && docker compose ps
echo "== kline table exists? =="; docker exec InStockDbService mariadb -uroot -proot instockdb -e "show tables like 'cn_stock_daily_kline';" 2>/dev/null
echo BASELINE_DONE
