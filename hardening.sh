#!/bin/sh
# 阶段0加固: swap2G / 首次备份 / 每日备份cron / 构建缓存清理
set +e
echo "== 1 swap =="
if swapon --show 2>/dev/null | grep -q swapfile; then
  echo "swap already exists"
else
  fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
free -h
swapon --show

echo "== 2 run one backup =="
sh /data/instock/backup_db.sh
ls -lh /data/instock/backup/

echo "== 3 install daily backup crontab (03:17) =="
( crontab -l 2>/dev/null | grep -v backup_db.sh; echo '17 3 * * * /data/instock/backup_db.sh >> /data/instock/backup/backup.log 2>&1' ) | crontab -
echo "--- root crontab ---"; crontab -l

echo "== 4 builder prune (unused build cache only) =="
docker builder prune -f
docker system df
echo HARDEN_DONE
