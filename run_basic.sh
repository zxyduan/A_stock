#!/bin/sh
# 启动 basic_data_daily_job(无参=最近交易日, before=False 真实落表), 看初始日志与现有表
set +e
docker exec -d InStock sh -lc "cd /data/InStock && PYTHONPATH=/data/InStock python3 instock/job/basic_data_daily_job.py > /tmp/basic_manual.log 2>&1"
echo "basic started detached"
sleep 12
echo "=== LOG (basic_manual) ==="
docker exec InStock sh -lc "tail -30 /tmp/basic_manual.log 2>/dev/null || echo no-log"
echo "=== TABLES in instockdb ==="
docker exec InStockDbService sh -lc "mariadb -uroot -proot instockdb -e 'show tables;' 2>/dev/null || mysql -uroot -proot instockdb -e 'show tables;' 2>/dev/null"
echo RUN_BASIC_BOOT_DONE
