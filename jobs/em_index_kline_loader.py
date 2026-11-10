#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
em_index_kline_loader.py —— #6 宽基指数日线（② 可达待新写，源 push2his kline）

默认 DRY_RUN=1：只拉取统计、打印每指数交易日数，不写库。
实写前置：备份 + gap_ddl_review.sql 中 cn_index_daily 建表 + IDX_DRY_RUN=0。

环境变量：
  IDX_DRY_RUN=1(默认)
  IDX_START=20210101   IDX_END=yyyyMMdd(默认今天)
  IDX_LIMIT=0          只处理白名单前 N 个（灰度用）
  IDX_WHITELIST=""     覆盖内置白名单，格式 secid:code:name,secid:code:name
内置白名单均已在 2026-11-10 探针验证 rc=0/klines 非空。
容器内运行：
  cd /data/InStock && PYTHONPATH=/data/InStock python3 instock/cache/em_index_kline_loader.py
"""
import os
import datetime
import em_common as ec

TAG = "em_index"
TABLE = "cn_index_daily"
COLS = ["index_code", "name", "date", "open", "close", "high", "low",
        "volume", "amount", "adjust", "source"]

# secid: code:name（1=沪市指数, 0=深市指数）
DEFAULT_WL = [
    ("1.000300", "000300", "沪深300"),
    ("1.000905", "000905", "中证500"),
    ("0.399006", "399006", "创业板指"),
    ("1.000001", "000001", "上证综指"),
    ("1.000016", "000016", "上证50"),
    ("0.399001", "399001", "深证成指"),
]


def parse_whitelist():
    raw = os.environ.get("IDX_WHITELIST", "").strip()
    if not raw:
        return DEFAULT_WL
    out = []
    for item in raw.split(","):
        parts = item.split(":")
        if len(parts) >= 3:
            out.append((parts[0], parts[1], parts[2]))
    return out or DEFAULT_WL


def main():
    dry = ec.env_flag("IDX_DRY_RUN", True)
    limit = ec.env_int("IDX_LIMIT", 0)
    beg = os.environ.get("IDX_START", "20210101")
    end = os.environ.get("IDX_END", datetime.date.today().strftime("%Y%m%d"))
    wl = parse_whitelist()
    if limit:
        wl = wl[:limit]

    s = ec.session()
    all_rows = []
    for secid, code, name in wl:
        try:
            em_name, klines = ec.kline_index(secid, beg, end, s=s)
            display = em_name or name
            mapped = [{
                "index_code": code, "name": display, "date": k["date"],
                "open": k["open"], "close": k["close"], "high": k["high"],
                "low": k["low"], "volume": k["volume"], "amount": k["amount"],
                "adjust": "raw", "source": "EM_PUSH2HIS_KLINE",
            } for k in klines]
            all_rows.extend(mapped)
            ec.log(TAG, "%s %s rows=%d (%s~%s)" % (code, display, len(mapped),
                    mapped[0]["date"] if mapped else "-",
                    mapped[-1]["date"] if mapped else "-"))
        except Exception as e:
            ec.log(TAG, "%s %s FAIL %r" % (secid, code, e))

    ec.log(TAG, "total_rows=%d dry_run=%s" % (len(all_rows), dry))
    if dry:
        if all_rows:
            print("SAMPLE", all_rows[0])
        ec.log(TAG, "DRY_RUN 未写库；建表并确认后设 IDX_DRY_RUN=0 实写")
        return

    conn = ec.conn()
    cur = conn.cursor()
    if not ec.table_exists(cur, TABLE):
        ec.log(TAG, "目标表 %s 不存在：先执行 gap_ddl_review.sql，已中止写库" % TABLE)
        conn.close()
        return
    n = ec.insert_ignore(cur, TABLE, COLS, all_rows)
    conn.commit()
    conn.close()
    ec.log(TAG, "INSERT IGNORE rows=%d" % n)


if __name__ == "__main__":
    main()
