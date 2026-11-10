#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
em_valuation_loader.py —— #2 估值时序(PE/PB/PS)截面增量【DRY 骨架；不建表、不回填历史】

数据来源：库内 cn_stock_selection 收盘截面（无免费历史长序列，前期只读探针已证伪外部回填；
selection 本身仅最近数个交易日截面，故本采集器只做“当日截面 -> 时序表”的增量搬运）。

默认 VAL_DRY_RUN=1：只读统计 + 打印样例，绝不写库。
实写前置（缺一不可，且默认不执行）：
  1) 先备份 instockdb；
  2) 按 ops/gap_extra_review.sql 2.1 注释段建 cn_stock_valuation_daily(PK code,date)；
  3) VAL_DRY_RUN=0 且 table_exists 守卫通过，才 upsert 当日截面。

口径纪律：
  * 分位/排序前默认剔除 pe9/pbnewmrq/ps9 的 NULL 与非正值（亏损股负 PE 无估值含义）；
  * 不承诺历史回填，时序长度随交易日自然累积；
  * 不调用外部行情/估值接口、不改 cron、不重启。

环境变量：
  VAL_DRY_RUN=1(默认)           1=只读统计不写库；0=在表存在前提下 upsert
  VAL_DATE=""                   指定截面日期 YYYY-MM-DD；留空=最近一个 MAX(date)
  VAL_LIMIT=0                   灰度只处理前 N 行；0=不限
  VAL_KEEP_NONPOS=0(默认False)  1=保留 pe/pb/ps 非正值（不建议用于分位计算）
  VAL_DROP_NULL=1(默认True)      1=剔除任一估值为 NULL 的行
容器内干跑：
  cd /data/InStock && PYTHONPATH=/data/InStock python3 instock/cache/em_valuation_loader.py
"""
import json
import os
import em_common as ec

TAG = "em_valuation"
TABLE = "cn_stock_valuation_daily"
COLS = ["code", "date", "pe9", "pbnewmrq", "ps9", "source"]


def load_snapshot(snap_date):
    """只读拉取 selection 指定截面；无外部请求。返回 list[dict]。"""
    conn = ec.conn()
    cur = conn.cursor()
    if snap_date:
        cur.execute(
            "SELECT code, date, pe9, pbnewmrq, ps9 FROM cn_stock_selection "
            "WHERE date=%s ORDER BY code", (snap_date,))
    else:
        cur.execute(
            "SELECT code, date, pe9, pbnewmrq, ps9 FROM cn_stock_selection "
            "WHERE date=(SELECT MAX(date) FROM cn_stock_selection) ORDER BY code")
    rows = [dict(zip(("code", "date", "pe9", "pbnewmrq", "ps9"), r))
            for r in cur.fetchall()]
    cur.close()
    conn.close()
    return rows


def clean(rows, keep_nonpos, drop_null):
    """按口径清洗：剔 NULL / 非正值；返回 (kept, stat)。"""
    stat = dict(fetched=len(rows), null=0, nonpos=0, kept=0)
    out = []
    for r in rows:
        pe = ec.fnum(r.get("pe9"))
        pb = ec.fnum(r.get("pbnewmrq"))
        ps = ec.fnum(r.get("ps9"))
        if drop_null and (pe is None or pb is None or ps is None):
            stat["null"] += 1
            continue
        if not keep_nonpos and (
                (pe is not None and pe <= 0) or
                (pb is not None and pb <= 0) or
                (ps is not None and ps <= 0)):
            stat["nonpos"] += 1
            continue
        out.append({
            "code": r.get("code"),
            "date": ec.to_date(r.get("date")),
            "pe9": pe, "pbnewmrq": pb, "ps9": ps,
            "source": "FROM_SELECTION_SNAPSHOT",
        })
    stat["kept"] = len(out)
    return out, stat


def main():
    dry = ec.env_flag("VAL_DRY_RUN", True)
    snap_date = os.environ.get("VAL_DATE", "").strip() or None
    limit = ec.env_int("VAL_LIMIT", 0)
    keep_nonpos = ec.env_flag("VAL_KEEP_NONPOS", False)
    drop_null = ec.env_flag("VAL_DROP_NULL", True)

    raw = load_snapshot(snap_date)
    observed_date = raw[0]["date"] if raw else None
    if limit:
        raw = raw[:limit]

    mapped, stat = clean(raw, keep_nonpos, drop_null)
    ec.log(TAG, "snapshot_date=%s fetched=%d kept=%d dropped_null=%d dropped_nonpos=%d "
                "keep_nonpos=%s dry_run=%s"
           % (observed_date, stat["fetched"], stat["kept"], stat["null"],
              stat["nonpos"], keep_nonpos, dry))

    if dry:
        for m in mapped[:3]:
            print(json.dumps(m, ensure_ascii=False, default=str))
        ec.log(TAG, "DRY_RUN 未写库、无历史回填；建表并核对口径后再 VAL_DRY_RUN=0 做当日增量")
        return

    conn = ec.conn()
    cur = conn.cursor()
    if not ec.table_exists(cur, TABLE):
        ec.log(TAG, "目标表 %s 不存在：先按 gap_extra_review.sql 2.1 建表，已中止写库" % TABLE)
        conn.close()
        return
    n = ec.upsert_many(cur, TABLE, COLS, mapped,
                       update_columns=["pe9", "pbnewmrq", "ps9", "source"])
    conn.commit()
    conn.close()
    ec.log(TAG, "upsert processed rows=%d (PK code,date；重复日刷新估值，不回写主键)" % n)


if __name__ == "__main__":
    main()
