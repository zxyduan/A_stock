#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
em_dividend_loader.py —— #3 分红送配与股息率历史（① 现成可拿，源 RPT_SHAREBONUS_DET）

默认 DRY_RUN=1：只拉取、统计、打印样例，不写库。
实写前置：
  1) 先备份；2) 先执行 ops/gap_ddl_review.sql 中 cn_stock_dividend 段建表；
  3) DIV_DRY_RUN=0 且目标表存在才会 INSERT IGNORE。

环境变量：
  DIV_DRY_RUN=1(默认)        1=只统计不写库；0=实写
  DIV_LIMIT=0                只处理前 N 条（灰度用，0=不限）
  DIV_REPORT_DATES=""        逗号分隔报告期，如 2023-12-31,2022-12-31；留空=最新公告流
  CACHE_DIR                  进度文件目录（默认 /data/InStock/instock/cache）
容器内运行：
  cd /data/InStock && PYTHONPATH=/data/InStock python3 instock/cache/em_dividend_loader.py
"""
import json
import em_common as ec

TAG = "em_dividend"
TABLE = "cn_stock_dividend"
COLS = [
    "code", "secucode", "name", "report_date", "plan_notice_date",
    "equity_record_date", "ex_dividend_date", "pretax_bonus_rmb",
    "bonus_ratio", "it_ratio", "divident_ratio", "assign_progress",
    "plan_profile", "total_shares", "basic_eps", "bvps", "source", "raw_json",
]


def map_row(x):
    code = x.get("SECURITY_CODE")
    if not code:
        return None
    return {
        "code": code,
        "secucode": x.get("SECUCODE"),
        "name": x.get("SECURITY_NAME_ABBR"),
        "report_date": ec.to_date(x.get("REPORT_DATE")),
        "plan_notice_date": ec.to_date(x.get("PLAN_NOTICE_DATE")),
        "equity_record_date": ec.to_date(x.get("EQUITY_RECORD_DATE")),
        "ex_dividend_date": ec.to_date(x.get("EX_DIVIDEND_DATE")),
        "pretax_bonus_rmb": ec.fnum(x.get("PRETAX_BONUS_RMB")),
        "bonus_ratio": ec.fnum(x.get("BONUS_RATIO")),
        "it_ratio": ec.fnum(x.get("IT_RATIO")),
        "divident_ratio": ec.fnum(x.get("DIVIDENT_RATIO")),
        "assign_progress": x.get("ASSIGN_PROGRESS"),
        "plan_profile": x.get("IMPL_PLAN_PROFILE"),
        "total_shares": ec.fnum(x.get("TOTAL_SHARES")),
        "basic_eps": ec.fnum(x.get("BASIC_EPS")),
        "bvps": ec.fnum(x.get("BVPS")),
        "source": "EM_RPT_SHAREBONUS_DET",
        "raw_json": ec.raw_json(x),
    }


def main():
    dry = ec.env_flag("DIV_DRY_RUN", True)
    limit = ec.env_int("DIV_LIMIT", 0)
    only_imp = ec.env_flag("DIV_ONLY_IMPLEMENTED", True)
    dates = [d.strip() for d in __import__("os").environ.get("DIV_REPORT_DATES", "").replace(" ", "").split(",") if d.strip()]

    raw = []
    cap = limit or None
    if dates:
        for rd in dates:
            ec.log(TAG, "fetch report_date=%s" % rd)
            raw.extend(ec.dc_fetch("RPT_SHAREBONUS_DET",
                                   extra_filter="(REPORT_DATE='%s')" % rd, max_rows=cap))
            if cap and len(raw) >= cap:
                break
    else:
        ec.log(TAG, "fetch latest announcement stream (no report-date filter)")
        raw = ec.dc_fetch("RPT_SHAREBONUS_DET", max_rows=cap)

    if limit:
        raw = raw[:limit]
    mapped = [m for m in (map_row(x) for x in raw) if m]
    pre = len(mapped)
    if only_imp:
        mapped = [m for m in mapped if (m.get("assign_progress") or "") == "实施分配"]
    ec.log(TAG, "fetched=%d mapped=%d only_implemented=%s kept=%d dropped=%d dry_run=%s"
           % (len(raw), pre, only_imp, len(mapped), pre - len(mapped), dry))

    if dry:
        for m in mapped[:3]:
            print(json.dumps(m, ensure_ascii=False, default=str))
        ec.log(TAG, "DRY_RUN 未写库；建表并确认字段后设 DIV_DRY_RUN=0 实写")
        return

    conn = ec.conn()
    cur = conn.cursor()
    if not ec.table_exists(cur, TABLE):
        ec.log(TAG, "目标表 %s 不存在：先执行 gap_ddl_review.sql 对应段，已中止写库" % TABLE)
        conn.close()
        return
    n = ec.insert_ignore(cur, TABLE, COLS, mapped)
    conn.commit()
    conn.close()
    ec.log(TAG, "INSERT IGNORE rows=%d (含重复跳过)" % n)


if __name__ == "__main__":
    main()
