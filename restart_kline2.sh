#!/bin/sh
# 提速重启: 保留done断点, workers=10, 短sleep; 不清表不清done
set +e
for p in $(docker top InStock 2>/dev/null | grep kline_history_loader | awk '{print $2}'); do kill "$p" 2>/dev/null && echo "killed $p"; done
sleep 4
docker top InStock 2>/dev/null | grep kline_history_loader || echo "stopped"

nohup docker exec InStock sh -c 'cd /data/InStock && PYTHONPATH=/data/InStock KLINE_START=20210101 KLINE_WORKERS=10 python3 instock/cache/kline_history_loader.py >> /data/InStock/instock/cache/kline_history.log 2>&1' >/data/instock/app/cache/kline_host.out 2>&1 &
echo "launcher=$!"
sleep 15
echo "== proc =="; docker top InStock | grep kline_history_loader
echo "== log =="; tail -n 8 /data/instock/app/cache/kline_history.log
echo "== done/failed =="; wc -l /data/instock/app/cache/kline_done.txt /data/instock/app/cache/kline_failed.txt 2>/dev/null
echo RESTART2_DONE
