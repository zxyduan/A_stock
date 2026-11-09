#!/bin/sh
# 只读证据采集: 服务状态/端口/调度/表行数/资源, 供部署文档回填
set +e
echo "===== 1. compose ps ====="
cd /data/instock && docker compose ps
echo "===== 2. images ====="
docker images --format '{{.Repository}}:{{.Tag}}  ID={{.ID}}  Size={{.Size}}' | grep -Ei 'instock|mariadb|python'
echo "===== 3. web 9988 ====="
curl -sS -m8 -o /dev/null -w "GET /instock/ -> %{http_code}\n" http://127.0.0.1:9988/instock/
echo "===== 4. host listening (9988/3306/9001) ====="
ss -tlnp 2>/dev/null | grep -E ':9988|:3306|:9001' || echo "no extra public listener"
echo "===== 5. container crontab ====="
docker exec InStock sh -c 'ls -la /var/spool/cron/crontabs/ 2>/dev/null; echo ---ROOT---; cat /var/spool/cron/crontabs/root 2>/dev/null; echo ---ETC-CRON---; ls -la /etc/cron.d 2>/dev/null'
echo "===== 6. key processes ====="
docker exec InStock sh -c 'for p in /proc/[0-9]*; do c=$(tr "\0" " " < $p/cmdline 2>/dev/null); case "$c" in *web_service*|*execute_daily*|*cron*|*basic_data*) echo "$c";; esac; done'
echo "===== 7. DB tables (approx rows) ====="
docker exec InStockDbService mariadb -uroot -proot -e "SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema='instockdb' ORDER BY table_name;" 2>/dev/null
echo "===== 8. exact counts ====="
for t in cn_stock_spot cn_etf_spot cn_stock_selection cn_stock_spot_buy cn_stock_bonus cn_stock_lhb cn_stock_blocktrade cn_stock_limitup_reason; do
  printf "EXACT %-22s " "$t"
  docker exec InStockDbService mariadb -uroot -proot instockdb -e "SELECT COUNT(*) c FROM $t;" 2>/dev/null | tail -1
done
echo "===== 9. persistence size / disk / mem ====="
du -sh /data/instock/mariadb/data 2>/dev/null
df -h / | tail -1
free -h | head -2
echo COLLECT_FINAL_DONE
