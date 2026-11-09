#!/bin/sh
# 只读: 查容器内 cron run-parts 目录到底挂了哪些作业脚本(判断无人值守是否真触发作业)
set +e
echo "===== ls cron dirs ====="
docker exec InStock ls -la /etc/cron.hourly /etc/cron.workdayly /etc/cron.monthly 2>&1
echo "===== job scripts content ====="
docker exec InStock sh -c 'find /etc/cron.hourly /etc/cron.workdayly /etc/cron.monthly -type f 2>/dev/null | while read f; do echo "=== $f ==="; head -25 "$f"; done'
echo "===== cron process ====="
docker exec InStock sh -c 'ps aux 2>/dev/null | grep cron | grep -v grep || ls /usr/sbin/cron'
echo CRON_PROBE_DONE
