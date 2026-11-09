#!/bin/sh
# 检查 basic 进程/日志, ETF表是否建成, 并直接复现 fund_etf_spot_em
set +e
echo "=== proc scan basic_data ==="
docker exec InStock sh -lc 'for p in /proc/[0-9]*; do c=$(tr "\0" " " < $p/cmdline 2>/dev/null); case "$c" in *basic_data*) echo "$p: $c";; esac; done; echo scan-end'
echo "=== basic log (lines + tail) ==="
docker exec InStock sh -lc "wc -l /tmp/basic_manual.log 2>/dev/null; tail -40 /tmp/basic_manual.log 2>/dev/null"
echo "=== cn_etf_spot table/count ==="
docker exec InStockDbService sh -lc "mariadb -uroot -proot instockdb -e 'SHOW TABLES LIKE \"cn_etf_spot\"; SELECT COUNT(*) AS etf_rows FROM cn_etf_spot;' 2>&1"
echo "=== direct fund_etf_spot_em() ==="
docker exec InStock sh -lc "cd /data/InStock && PYTHONPATH=/data/InStock python3 -c 'import instock.core.crawling.fund_etf_em as m; d=m.fund_etf_spot_em(); print(\"ETF_ROWS\", None if d is None else len(d))' 2>&1 | tail -25"
echo POLL_ETF_DONE
