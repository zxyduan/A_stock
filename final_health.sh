#!/bin/sh
# 最终健康确认(只读): 容器/Web/supervisor程序/近期错误关键字
set +e
echo "=== compose ps ==="
cd /data/instock && docker compose ps
echo "=== web ==="
curl -sS -m8 -o /dev/null -w "web_code=%{http_code}\n" http://127.0.0.1:9988/instock/
echo "=== supervisorctl status ==="
docker exec InStock supervisorctl status 2>&1
echo "=== recent error keywords in app log ==="
docker logs --tail 80 InStock 2>&1 | grep -Ei "Traceback|处理异常|JSONDecodeError|read-only" | tail -20 || true
echo "=== counts sanity ==="
docker exec InStockDbService mariadb -uroot -proot instockdb -e \
 "SELECT (SELECT COUNT(*) FROM cn_stock_spot) spot, (SELECT COUNT(*) FROM cn_etf_spot) etf, (SELECT COUNT(*) FROM cn_stock_selection) sel;" 2>/dev/null
echo HEALTH_DONE
