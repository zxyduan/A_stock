#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
em_org_holding_loader.py —— #8c 机构持仓明细（源 RPT_MAINDATA_MAIN_POSITIONDETAILS；季频）

粒度：一行 = 某报告期某只机构持有某股票（非每票汇总），主键 (code,report_date,holder_name)。
字段全部来自 2026-11-10 只读实测返回。默认 DRY_RUN=1。
实写前置：备份 + gap_p2_ddl_review.sql 中 cn_stock_org_holding 建表 + ORG_DRY_RUN=0。

环境变量：
  ORG_DRY_RUN=1(默认)
  ORG_LIMIT=0
  ORG_REPORT_DATE="" 指定报告期(yyyy-mm-dd)过滤；留空=按流抽样
容器内运行：
  cd /data/InStock && PYTHONPATH=/data/InStock python3 instock/cache/em_org_holding_loader.py
"""
import os
import em_common as ec

TAG = "em_org"
TABLE = "cn_stock_org_holding"
COLS = ["code", "name", "report_date", "holder_name", "org_type",
        "total_shares", "shares_ratio", "netasset_ratio", "hold_mktcap",
        "source", "raw_json"]


def map_row(x):
    code = x.get("SECURITY_CODE")
    holder = x.get("HOLDER_NAME")
    if not code or not holder:
        return None
    return {
        "code": code,
        "name": x.get("SECURITY_NAME_ABBR"),
        "report_date": ec.to_date(x.get("REPORT_DATE")),
        "holder_name": holder,
        "org_type": x.get("ORG_TYPE"),
        "total_shares": ec.fnum(x.get("TOTAL_SHARES")),
        "shares_ratio": ec.fnum(x.get("TOTAL_SHARES_RATIO")),
        "netasset_ratio": ec.fnum(x.get("NETASSET_RATIO")),
        "hold_mktcap": ec.fnum(x.get("HOLD_MARKET_CAP")),
        "source": "EM_RPT_MAINDATA_MAIN_POSITIONDETAILS",
        "raw_json": ec.raw_json(x),
    }


def main():
    dry = ec.env_flag("ORG_DRY_RUN", True)
    limit = ec.env_int("ORG_LIMIT", 0)
    rd = os.environ.get("ORG_REPORT_DATE", "").strip()
    flt = "(REPORT_DATE='%s')" % rd if rd else None

    raw = ec.dc_fetch("RPT_MAINDATA_MAIN_POSITIONDETAILS", extra_filter=flt,
                      max_rows=limit or None)
    if limit:
        raw = raw[:limit]
    mapped = [m for m in (map_row(x) for x in raw) if m]
    ec.log(TAG, "fetched=%d mapped=%d dry_run=%s filter=%s"
           % (len(raw), len(mapped), dry, flt or "none"))

    if dry:
        for m in mapped[:3]:
            print("SAMPLE", m)
        ec.log(TAG, "DRY_RUN 未写库；建表并核对单位后设 ORG_DRY_RUN=0 实写")
        return

    conn = ec.conn()
    cur = conn.cursor()
    if not ec.table_exists(cur, TABLE):
        ec.log(TAG, "目标表 %s 不存在：先执行 gap_p2_ddl_review.sql，已中止写库" % TABLE)
        conn.close()
        return
    n = ec.insert_ignore(cur, TABLE, COLS, mapped)
    conn.commit()
    conn.close()
    ec.log(TAG, "INSERT IGNORE rows=%d" % n)


if __name__ == "__main__":
    main()
