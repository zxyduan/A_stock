#!/usr/bin/env bash
# 工作日盘后增量补抓前复权日线（近 12 自然日窗口，INSERT IGNORE 幂等，重跑不重复）。
# 由宿主 crontab 17:45 工作日调用；也可手动: bash /data/instock/ops/kline_delta.sh
set -u
ROOT=/data/instock
mkdir -p "$ROOT/app/log"
START=$(date -d "-12 days" +%Y%m%d)
END=$(date +%Y%m%d)
{
  echo "===== kline_delta run $(date '+%F %T') window=$START..$END adjust=qfq ====="
  docker exec \
    -e KLINE_START="$START" -e KLINE_END="$END" -e KLINE_ADJUST=qfq -e KLINE_WORKERS=4 \
    InStock python3 /data/InStock/instock/job/kline_delta_increment.py
  echo "===== kline_delta finished $(date '+%F %T') ====="
} >> "$ROOT/app/log/kline_delta.cron.log" 2>&1
