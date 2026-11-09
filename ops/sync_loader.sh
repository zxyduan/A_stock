#!/usr/bin/env bash
# 将仓内权威源 jobs/kline_history_loader.py 同步到容器执行副本 app/cache/ 并 md5 对账
# 用法: bash /data/instock/ops/sync_loader.sh
# loader 按需后台运行、非常驻, 同步脚本本身无需重启容器
set -euo pipefail
ROOT=/data/instock
SRC=$ROOT/jobs/kline_history_loader.py
DST=$ROOT/app/cache/kline_history_loader.py
cp "$SRC" "$DST"
S=$(md5sum "$SRC" | cut -d' ' -f1)
D=$(md5sum "$DST" | cut -d' ' -f1)
echo "$S  $SRC"
echo "$D  $DST"
[ "$S" = "$D" ] && echo "SYNC_OK" || { echo "SYNC_FAIL md5 mismatch"; exit 1; }
