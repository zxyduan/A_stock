#!/usr/bin/env bash
# =============================================================================
# sync_gap_loaders.sh  把 jobs/ 下缺口补全采集器源同步到容器运行目录 app/cache
# - 源文件受 git 跟踪(/data/instock/jobs)；运行副本 app/cache 被 .gitignore 忽略、不入库。
# - 只做拷贝，不执行、不写库、不改 cron。
# 用法: bash /data/instock/ops/sync_gap_loaders.sh
# =============================================================================
set -euo pipefail

SRC=/data/instock/jobs
DST=/data/instock/app/cache
mkdir -p "$DST"

for f in em_common.py em_dividend_loader.py em_index_kline_loader.py em_event_loader.py em_holder_loader.py em_org_holding_loader.py em_financial_loader.py em_valuation_loader.py; do
  if [ ! -f "$SRC/$f" ]; then
    echo "MISSING_SOURCE $SRC/$f"; exit 1
  fi
  install -m 0644 "$SRC/$f" "$DST/$f"
  echo "synced $f -> $DST/$f"
done

echo
echo "下一步（默认 DRY_RUN，不写库）："
echo "  bash /data/instock/ops/run_gap_loader.sh dividend"
echo "  bash /data/instock/ops/run_gap_loader.sh index"
echo "  bash /data/instock/ops/run_gap_loader.sh event"
echo "  bash /data/instock/ops/run_gap_loader.sh holder"
echo "  bash /data/instock/ops/run_gap_loader.sh org"
echo "  bash /data/instock/ops/run_gap_loader.sh valuation"
echo "实写前置：先备份 + 执行 gap_ddl_review.sql 对应段；再 APPLY=1 bash ops/run_gap_loader.sh <name>"
