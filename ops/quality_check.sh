#!/bin/sh
# 历史日线数据质量核查: 主键去重/覆盖完整度/行数分布/空值/抽样
set +e
docker exec InStockDbService mariadb -uroot -proot instockdb -e "
SELECT COUNT(*) total_rows, COUNT(DISTINCT code,date,adjust) distinct_key FROM cn_stock_daily_kline;
SELECT COUNT(*) missing_codes FROM (SELECT DISTINCT code FROM cn_stock_spot) s
  LEFT JOIN (SELECT DISTINCT code FROM cn_stock_daily_kline) k USING(code) WHERE k.code IS NULL;
SELECT COUNT(*) AS codes, MIN(cnt) min_rows, MAX(cnt) max_rows, ROUND(AVG(cnt),0) avg_rows
  FROM (SELECT code, COUNT(*) cnt FROM cn_stock_daily_kline GROUP BY code) t;
SELECT code, name, COUNT(*) cnt, MIN(date) first_d, MAX(date) last_d
  FROM cn_stock_daily_kline WHERE code IN ('600519','000001','300750','601398') GROUP BY code,name;
SELECT COUNT(*) null_ohlc FROM cn_stock_daily_kline WHERE open IS NULL OR close IS NULL OR high IS NULL OR low IS NULL;
SELECT code, name, COUNT(*) cnt FROM cn_stock_daily_kline GROUP BY code,name ORDER BY cnt ASC LIMIT 10;
SELECT date, COUNT(*) codes_that_day FROM cn_stock_daily_kline WHERE date IN ('2021-01-04','2024-01-02','2026-11-06') GROUP BY date ORDER BY date;
"
echo QC_DONE
