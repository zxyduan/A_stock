#!/bin/bash
# InStock MySQL 逻辑备份(gzip), 保留14天; 建议宿主 crontab 每日 03:17
set -e
mkdir -p /data/instock/backup
F=/data/instock/backup/instockdb_$(date +%Y%m%d_%H%M).sql.gz
docker exec InStockDbService sh -c 'mariadb-dump -uroot -proot --single-transaction --routines --triggers instockdb' \
  | gzip > "$F"
# 清理14天前旧备份
find /data/instock/backup -name 'instockdb_*.sql.gz' -mtime +14 -delete
ls -lh "$F"
echo "BACKUP_OK $F"
