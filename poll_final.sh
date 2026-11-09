#!/bin/sh
# 综合核查: basic进程/日志 + 全表近似行数 + 重点表精确行数
set +e
echo "=== proc basic_data ==="
docker exec InStock sh -c 'for p in /proc/[0-9]*; do c=$(tr "\0" " " < $p/cmdline 2>/dev/null); case "$c" in *basic_data*) echo "BASIC_RUNNING $p";; esac; done; echo scan-end'
echo "=== basic log ==="
docker exec InStock sh -c "wc -l /tmp/basic_manual.log 2>/dev/null; echo ---; tail -20 /tmp/basic_manual.log 2>/dev/null"
echo "=== all tables approx rows ==="
docker exec InStockDbService mariadb -uroot -proot -e "SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema='instockdb' ORDER BY table_name;" 2>/dev/null
echo "=== exact counts (key tables; 无表/0 会空) ==="
for t in cn_stock_spot cn_etf_spot cn_stock_selection cn_stock_indicators cn_stock_indicators_buy cn_stock_indicators_sell; do
  printf "%-28s " "$t"
  docker exec InStockDbService mariadb -uroot -proot instockdb -e "SELECT COUNT(*) AS c FROM $t;" 2>/dev/null | tail -1
done
echo POLL_FINAL_DONE
