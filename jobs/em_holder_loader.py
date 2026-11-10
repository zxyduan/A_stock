#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
em_holder_loader.py —— #8b 股东户数时序（源 RPT_F10_EH_HOLDERNUM；季频/不定期披露）

字段全部来自 2026-11-10 只读实测返回，禁止使用未出现在响应中的字段名。
默认 DRY_RUN=1。实写前置：备份 + gap_p2_ddl_review.sql 中 cn_stock_holder 建表 + HOLD_DRY_RUN=0。

环境变量：
  HOLD_DRY_RUN=1(默认)
  HOLD_LIMIT=0
  HOLD_END_DATE=""   指定报告期末(yyyy-mm-dd)过滤，如 2026-09-30；留空=按最新流抽样
  CACHE_DIR          进度目录
容器内运行：
  cd /data/InStock && PYTHONPATH=/data/InStock python3 instock/cache/em_holder_loader.py
"""
import os
import em_common as ec

TAG = "em_holder"
TABLE = "cn_stock_holder"
COLS = ["code", "name", "end_date", "holder_total_num", "num_change",
        "total_num_ratio", "avg_total_shares", "avg_hold_amt",
        "notice_date", "source", "raw_json"]


def map_row(x):
    code = x.get("SECURITY_CODE")
    if not code:
        return None
    return {
        "code": code,
        "name": x.get("SECURITY_NAME_ABBR"),
        "end_date": ec.to_date(x.get("END_DATE")),
        "holder_total_num": ec.fnum(x.get("HOLDER_TOTAL_NUM")),
        "num_change": ec.fnum(x.get("HOLDER_TOTAL_NUMCHANGE")),
        "total_num_ratio": ec.fnum(x.get("TOTAL_NUM_RATIO")),
        "avg_total_shares": ec.fnum(x.get("AVG_TOTAL_SHARES")),
        "avg_hold_amt": ec.fnum(x.get("AVG_HOLD_AMT")),
        "notice_date": ec.to_date(x.get("NOTICE_DATE")),
        "source": "EM_RPT_F10_EH_HOLDERNUM",
        "raw_json": ec.raw_json(x),
    }


def main():
    dry = ec.env_flag("HOLD_DRY_RUN", True)
    limit = ec.env_int("HOLD_LIMIT", 0)
    end = os.environ.get("HOLD_END_DATE", "").strip()
    flt = "(END_DATE='%s')" % end if end else None

    raw = ec.dc_fetch("RPT_F10_EH_HOLDERNUM", extra_filter=flt,
                      max_rows=limit or None)
    if limit:
        raw = raw[:limit]
    mapped = [m for m in (map_row(x) for x in raw) if m]
    ec.log(TAG, "fetched=%d mapped=%d dry_run=%s filter=%s"
           % (len(raw), len(mapped), dry, flt or "none"))

    if dry:
        for m in mapped[:3]:
            print("SAMPLE", m)
        ec.log(TAG, "DRY_RUN 未写库；建表并核对单位后设 HOLD_DRY_RUN=0 实写")
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
