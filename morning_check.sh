#!/bin/sh
# 明早一键核查: 服务 / 入库进度 / 数据覆盖 / 失败 / 资源 / 备份
set +e
echo "===== 1. 服务状态 ====="
cd /data/instock && docker compose ps
curl -sS -m5 -o /dev/null -w "web_http=%{http_code}\n" http://127.0.0.1:9988/instock/

echo "===== 2. 入库进程(无输出=已结束) ====="
docker top InStock | grep kline_history_loader || echo "loader: 已结束"

echo "===== 3. 入库日志结尾 / 计数 ====="
tail -n 4 /data/instock/app/cache/kline_history.log
echo "-- done / failed 行数 --"
wc -l /data/instock/app/cache/kline_done.txt /data/instock/app/cache/kline_failed.txt 2>/dev/null

echo "===== 4. 表覆盖统计 ====="
docker exec InStockDbService mariadb -uroot -proot instockdb -e \
 "SELECT COUNT(*) rows_cnt, COUNT(DISTINCT code) codes, MIN(date) min_date, MAX(date) max_date FROM cn_stock_daily_kline; SELECT adjust, COUNT(*) AS rows_cnt FROM cn_stock_daily_kline GROUP BY adjust;"

echo "===== 5. 失败代码样例(前20, 空=无失败) ====="
head -20 /data/instock/app/cache/kline_failed.txt 2>/dev/null || echo "none"

echo "===== 6. 资源 ====="
free -h
swapon --show
df -h /
docker system df

echo "===== 7. 备份与定时 ====="
ls -lh /data/instock/backup/*.sql.gz 2>/dev/null | tail -5
crontab -l | grep backup_db.sh
echo MORNING_CHECK_DONE
