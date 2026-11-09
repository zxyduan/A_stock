#!/bin/sh
# 轮询 basic 作业日志与关键表行数(不存在的表静默输出空行)
set +e
dbq() { docker exec InStockDbService sh -lc "mariadb -uroot -proot instockdb -e \"$1\" 2>/dev/null"; }
echo "=== basic_manual.log tail ==="
docker exec InStock sh -lc "tail -40 /tmp/basic_manual.log 2>/dev/null || echo no-log"
echo "=== row counts ==="
for t in cn_stock_spot cn_etf_spot cn_stock_selection cn_stock_indicators cn_stock_indicators_buy cn_stock_indicators_sell cn_stock_attention cn_stock_blocktrade cn_stock_bonus cn_stock_lhb cn_stock_limitup_reason cn_stock_chip_race_open cn_stock_chip_race_end; do
  printf "%-32s " "$t"
  dbq "SELECT COUNT(*) FROM $t;" | tail -n +2
done
echo "=== tables list ==="
dbq "show tables;"
echo POLL_BASIC_DONE
