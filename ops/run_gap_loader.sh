#!/usr/bin/env bash
# =============================================================================
# run_gap_loader.sh  缺口补全采集器薄包装（宿主 -> docker exec InStock python3）
# 默认 DRY_RUN=1：只拉取统计/打印样例，不写库。
# 显式 APPLY=1 才允许实写，且要求已备份、DDL 已建表（采集器自身也会再检查表存在）。
#
# 用法：
#   bash ops/run_gap_loader.sh dividend          # 干跑分红
#   bash ops/run_gap_loader.sh index             # 干跑宽基指数
#   bash ops/run_gap_loader.sh event             # 干跑解禁事件
#   DIV_LIMIT=20 bash ops/run_gap_loader.sh dividend          # 干跑只看前20条
#   APPLY=1 bash ops/run_gap_loader.sh dividend                # 实写(前置:备份+建表)
# 环境变量透传示例：IDX_START=20210101 APPLY=1 bash ops/run_gap_loader.sh index
# =============================================================================
set -euo pipefail

APP=InStock
case "${1:-}" in
  dividend) L=em_dividend_loader.py;     DRY=DIV_DRY_RUN ;;
  index)    L=em_index_kline_loader.py; DRY=IDX_DRY_RUN ;;
  event)    L=em_event_loader.py;       DRY=EVT_DRY_RUN ;;
  holder)   L=em_holder_loader.py;       DRY=HOLD_DRY_RUN ;;
  org)      L=em_org_holding_loader.py;DRY=ORG_DRY_RUN ;;
  financial) L=em_financial_loader.py; DRY=FIN_DRY_RUN ;;
  *) echo "usage: $0 dividend|index|event|holder|org|financial  [APPLY=1]"; exit 2 ;;
esac
shift || true

CACHE=/data/instock/app/cache
[ -f "$CACHE/$L" ] || { echo "missing $CACHE/$L; 先执行 bash /data/instock/ops/sync_gap_loaders.sh"; exit 3; }

if [ "${APPLY:-0}" = "1" ]; then
  echo "== APPLY(实写) $L  DRY=0  请确认已备份且 gap_ddl_review.sql 已建表 =="
  docker exec -e "$DRY=0" -e PYTHONPATH=/data/InStock -w /data/InStock "$APP" python3 instock/cache/$L
else
  echo "== DRY_RUN $L (不写库)；显式 APPLY=1 才实写 =="
  docker exec -e "$DRY=1" -e PYTHONPATH=/data/InStock -w /data/InStock "$APP" python3 instock/cache/$L
fi
