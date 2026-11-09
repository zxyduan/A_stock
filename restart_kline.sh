#!/bin/sh
# 统一全量: 停当前loader -> 清进度清单(保留表数据, INSERT IGNORE幂等) -> 宿主nohup重启全量2021起
set +e
echo "== stop existing loader =="
for p in $(docker top InStock 2>/dev/null | grep kline_history_loader | awk '{print $2}'); do kill "$p" 2>/dev/null && echo "killed host_pid=$p"; done
sleep 4
docker top InStock 2>/dev/null | grep kline_history_loader && echo "WARN still running" || echo "no loader now"

echo "== reset markers, keep table rows =="
: > /data/instock/app/cache/kline_done.txt
: > /data/instock/app/cache/kline_failed.txt
: > /data/instock/app/cache/kline_progress.txt
: > /data/instock/app/cache/kline_history.log

echo "== start full fetch (host nohup) =="
nohup docker exec InStock sh -c 'cd /data/InStock && PYTHONPATH=/data/InStock KLINE_START=20210101 KLINE_WORKERS=6 python3 instock/cache/kline_history_loader.py >> /data/InStock/instock/cache/kline_history.log 2>&1' >/data/instock/app/cache/kline_host.out 2>&1 &
echo "host_launcher_pid=$!"
sleep 12
echo "== docker top =="
docker top InStock | grep -E "kline_history|web_service"
echo "== log =="
tail -n 12 /data/instock/app/cache/kline_history.log
echo RESTART_DONE
