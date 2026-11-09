#!/bin/sh
# 运维手册事实采集: 服务/进程/作业清单/调度/表行数/资源/备份 (只读)
set +e
echo "===== A. compose / images ====="
cd /data/instock && docker compose ps
docker images | head -12

echo "===== B. supervisor programs ====="
docker exec InStock supervisorctl status

echo "===== C. app job files ====="
docker exec InStock sh -c 'ls -1 /data/InStock/instock/job/*.py | xargs -n1 basename'

echo "===== D. container cron ====="
docker exec InStock sh -c 'echo "--- crontab root ---"; cat /var/spool/cron/crontabs/root 2>/dev/null; echo "--- run_hourly ---"; cat /etc/cron.hourly/run_hourly 2>/dev/null; echo "--- run_workdayly ---"; cat /etc/cron.workdayly/run_workdayly 2>/dev/null; echo "--- run_monthly ---"; cat /etc/cron.monthly/run_monthly 2>/dev/null'

echo "===== E. tables overview (information_schema rows estimate) ====="
docker exec InStockDbService mariadb -uroot -proot instockdb -N -e "SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema='instockdb' ORDER BY table_name;"

echo "===== F. core exact counts + latest date ====="
docker exec InStockDbService mariadb --default-character-set=utf8mb4 -uroot -proot instockdb -e "
SELECT 'cn_stock_spot' AS t, COUNT(*) cnt, MAX(date) latest FROM cn_stock_spot
UNION ALL SELECT 'cn_etf_spot', COUNT(*), MAX(date) FROM cn_etf_spot
UNION ALL SELECT 'cn_stock_selection', COUNT(*), MAX(date) FROM cn_stock_selection
UNION ALL SELECT 'cn_stock_fund_flow', COUNT(*), MAX(date) FROM cn_stock_fund_flow
UNION ALL SELECT 'cn_stock_daily_kline', COUNT(*), MAX(date) FROM cn_stock_daily_kline;
SELECT COUNT(*) kline_rows, COUNT(DISTINCT code) codes, MIN(date) mn, MAX(date) mx FROM cn_stock_daily_kline;"

echo "===== G. host layout ====="
echo "--- /data/instock ---"; ls -1 /data/instock
echo "--- app/cache files ---"; ls -1 /data/instock/app/cache | head -40

echo "===== H. resources ====="
free -h; swapon --show; df -h /; docker system df

echo "===== I. backups ====="
ls -lh /data/instock/backup/*.sql.gz 2>/dev/null

echo "===== J. web + key procs ====="
curl -sS -m5 -o /dev/null -w "web_http=%{http_code}\n" http://127.0.0.1:9988/instock/
docker top InStock | grep -E "web_service|cron -f|kline_history" || echo "no batch proc"
echo COLLECT_DONE
