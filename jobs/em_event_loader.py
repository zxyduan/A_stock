#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
em_event_loader.py —— #8a 限售解禁事件（② 可达，源 RPT_LIFT_STAGE；并入统一事件表）

本期 event_type 仅写 lockup_unlock；表结构为后续 holder_change/repurchase 预留，
但本期不采集增减持/回购（对应报表未定位，见需求方案第二部分标记）。

默认 DRY_RUN=1。实写前置：备份 + gap_ddl_review.sql 中 cn_stock_event 建表 + EVT_DRY_RUN=0。

环境变量：
  EVT_DRY_RUN=1(默认)
  EVT_LIMIT=0
  EVT_FILTER=""   可选 datacenter filter，如 (FREE_DATE>='2026-01-01')；留空=近期全市场
容器内运行：
  cd /data/InStock && PYTHONPATH=/data/InStock python3 instock/cache/em_event_loader.py
"""
import os
import em_common as ec

TAG = "em_event"
TABLE = "cn_stock_event"
COLS = ["code", "name", "event_date", "event_type", "amount_shares",
        "amount_ratio", "event_mktcap", "detail", "source", "raw_json"]


def map_row(x):
    code = x.get("SECURITY_CODE")
    if not code:
        return None
    return {
        "code": code,
        "name": x.get("SECURITY_NAME_ABBR"),
        "event_date": ec.to_date(x.get("FREE_DATE")),
        "event_type": "lockup_unlock",
        "amount_shares": ec.fnum(x.get("FREE_SHARES")),
        "amount_ratio": ec.fnum(x.get("FREE_RATIO") or x.get("TOTAL_RATIO")),
        "event_mktcap": ec.fnum(x.get("LIFT_MARKET_CAP")),
        "detail": x.get("FREE_SHARES_TYPE"),
        "source": "EM_RPT_LIFT_STAGE",
        "raw_json": ec.raw_json(x),
    }


def main():
    dry = ec.env_flag("EVT_DRY_RUN", True)
    limit = ec.env_int("EVT_LIMIT", 0)
    only_a = ec.env_flag("EVT_A_SHARE_ONLY", True)
    flt = os.environ.get("EVT_FILTER", "").strip() or None

    raw = ec.dc_fetch("RPT_LIFT_STAGE", extra_filter=flt, max_rows=limit or None)
    if limit:
        raw = raw[:limit]
    mapped = [m for m in (map_row(x) for x in raw) if m]
    pre = len(mapped)
    if only_a:
        mapped = [m for m in mapped if ec.is_a_share(m["code"])]
    ec.log(TAG, "fetched=%d mapped=%d a_share_only=%s kept=%d dropped=%d dry_run=%s"
           % (len(raw), pre, only_a, len(mapped), pre - len(mapped), dry))

    if dry:
        for m in mapped[:3]:
            print("SAMPLE", m)
        ec.log(TAG, "DRY_RUN 未写库；建表并确认后设 EVT_DRY_RUN=0 实写")
        return

    conn = ec.conn()
    cur = conn.cursor()
    if not ec.table_exists(cur, TABLE):
        ec.log(TAG, "目标表 %s 不存在：先执行 gap_ddl_review.sql，已中止写库" % TABLE)
        conn.close()
        return
    n = ec.insert_ignore(cur, TABLE, COLS, mapped)
    conn.commit()
    conn.close()
    ec.log(TAG, "INSERT IGNORE rows=%d" % n)


if __name__ == "__main__":
    main()
