#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
em_financial_loader.py —— #1 季度财务关键科目【DRY 骨架，2026-11-10】

源报表（均 2026-11-10 只读实测 success:true，字段名以实测 KEYS 为准，不臆造）：
  main     RPT_F10_FINANCE_MAINFINADATA 165 字段（比率/EPS/金融专用）
  income   RPT_DMSK_FN_INCOME           46 字段（利润表绝对额, 元, 累计）
  balance  RPT_DMSK_FN_BALANCE          57 字段（资产负债表绝对额, 元, 时点；无 GOODWILL）
  cashflow RPT_DMSK_FN_CASHFLOW         48 字段（现金流净额, 元, 累计）

安全红线（与其它 em_* 采集器一致）：
  1) FIN_DRY_RUN 默认 1：只拉取/合并/打印样例，不连库写；
  2) 目标表 cn_stock_financial_quarter 不存在即中止写库（本批不建表、不 APPLY）；
  3) 金额保留源原值（实测单位=元），不做 ×1e4/×100 缩放；比率口径见列 COMMENT；
  4) 写库段已用 ON DUPLICATE KEY UPDATE(upsert_many)；但表不存在即中止、FIN_DRY_RUN 默认1，
     本批不建表不写库；正式放量仍需先建表、小样本灰度、确认三表按 code+report_date 对齐。

环境变量：
  FIN_DRY_RUN=1(默认)
  FIN_LIMIT=20              DRY 演示每个报表最大行数；正式 APPLY 设 0=不限
  FIN_A_SHARE_ONLY=1(默认) 仅保留沪深A股(0/3/6段),剔除北交所/三板
  FIN_CODE=""               单只调试(客户端过滤;报表不支持服务端SECURITY_CODE过滤)
  FIN_REPORT_DATES=""       逗号分隔季末(yyyy-mm-dd)服务端过滤,如 2025-12-31,2024-12-31;留空=首页抽样
  FIN_SOURCE=all            main/income/balance/cashflow/all
"""
import os
import json
import em_common as ec

TAG = "em_financial"
TABLE = "cn_stock_financial_quarter"

REPORTS = {
    "main": "RPT_F10_FINANCE_MAINFINADATA",
    "income": "RPT_DMSK_FN_INCOME",
    "balance": "RPT_DMSK_FN_BALANCE",
    "cashflow": "RPT_DMSK_FN_CASHFLOW",
}

# 目标白名单列（与 ops/gap_financial_ddl_review.sql 对齐；不含库默认 updated_at）
COLS = [
    "code", "name", "report_date", "report_type", "report_ann_date",
    "industry_code", "industry_name", "is_financial",
    "rev_total", "rev_yoy", "np_parent", "np_yoy", "np_deduct", "np_deduct_yoy",
    "eps_basic",
    "roe_weight", "gross_margin", "net_margin", "debt_asset_ratio",
    "current_ratio", "cash_ratio", "inv_turnover",
    "ocf", "ocf_to_np", "sales_cash",
    "cash_monetary", "accounts_receivable", "inventory", "fixed_asset",
    "accounts_payable", "total_assets", "total_liab", "total_equity",
    "fin_loans", "fin_deposits", "fin_npl_ratio", "fin_car",
    "fin_nbv_life", "fin_nbv_rate",
    "source", "raw_json",
]

# 金融行业关键词（粗判；正式版以 INDUSTRY_CODE 白名单细化，见 F1 规格 §5）
_FIN_KW = ("银行", "保险", "证券", "券商", "信托")


def _num(row, key):
    return ec.fnum(row.get(key)) if isinstance(row, dict) else None


def _pick(*vals):
    for v in vals:
        if v is not None:
            return v
    return None


def merge_one(bucket):
    """bucket: {report_key: source_row}；按 (code,report_date) 合并为一行白名单。"""
    main = bucket.get("main") or {}
    inc = bucket.get("income") or {}
    bal = bucket.get("balance") or {}
    cf = bucket.get("cashflow") or {}

    code = _pick(main.get("SECURITY_CODE"), inc.get("SECURITY_CODE"),
                 bal.get("SECURITY_CODE"), cf.get("SECURITY_CODE"))
    out = {c: None for c in COLS}
    out["code"] = code
    out["name"] = _pick(main.get("SECURITY_NAME_ABBR"), inc.get("SECURITY_NAME_ABBR"))
    out["report_date"] = ec.to_date(_pick(main.get("REPORT_DATE"), inc.get("REPORT_DATE"),
                                          bal.get("REPORT_DATE"), cf.get("REPORT_DATE")))
    out["report_type"] = main.get("REPORT_TYPE") or main.get("REPORT_DATE_NAME")
    out["report_ann_date"] = ec.to_date(_pick(main.get("NOTICE_DATE"), inc.get("NOTICE_DATE")))
    out["industry_code"] = _pick(inc.get("INDUSTRY_CODE"), bal.get("INDUSTRY_CODE"))
    out["industry_name"] = _pick(inc.get("INDUSTRY_NAME"), bal.get("INDUSTRY_NAME"))
    out["is_financial"] = int(any(k in (out["industry_name"] or "") for k in _FIN_KW))

    # 盈利：绝对额优先利润表，比率优先主指标宽表
    out["rev_total"] = _num(inc, "TOTAL_OPERATE_INCOME") or _num(main, "TOTALOPERATEREVE")
    out["rev_yoy"] = _num(main, "TOTALOPERATEREVETZ")
    out["np_parent"] = _num(inc, "PARENT_NETPROFIT") or _num(main, "PARENTNETPROFIT")
    out["np_yoy"] = _num(main, "PARENTNETPROFITTZ")
    out["np_deduct"] = _num(inc, "DEDUCT_PARENT_NETPROFIT") or _num(main, "KCFJCXSYJLR")
    out["np_deduct_yoy"] = _num(main, "KCFJCXSYJLRTZ")
    out["eps_basic"] = _num(main, "EPSJB")

    # 质量比率（百分数值/倍数口径见 DDL COMMENT；骨架不换算）
    out["roe_weight"] = _num(main, "ROEJQ")
    out["gross_margin"] = _num(main, "XSMLL")
    out["net_margin"] = _num(main, "XSJLL")
    out["debt_asset_ratio"] = _num(main, "ZCFZL") or _num(bal, "DEBT_ASSET_RATIO")
    out["current_ratio"] = _num(bal, "CURRENT_RATIO")          # 口径待核，先存原值
    out["cash_ratio"] = _num(main, "CASH_RATIO")
    out["inv_turnover"] = _num(main, "CHZZL")

    # 现金流（元,累计）
    out["ocf"] = _num(cf, "NETCASH_OPERATE")
    npv = out["np_parent"]
    if out["ocf"] is not None and npv:
        out["ocf_to_np"] = out["ocf"] / npv
    out["sales_cash"] = _num(cf, "SALES_SERVICES")

    # 资产负债（元,时点；工业口径,金融置空由 is_financial 标记）
    out["cash_monetary"] = _num(bal, "MONETARYFUNDS")
    out["accounts_receivable"] = _num(bal, "ACCOUNTS_RECE")
    out["inventory"] = _num(bal, "INVENTORY")
    out["fixed_asset"] = _num(bal, "FIXED_ASSET")
    out["accounts_payable"] = _num(bal, "ACCOUNTS_PAYABLE")
    out["total_assets"] = _num(bal, "TOTAL_ASSETS")
    out["total_liab"] = _num(bal, "TOTAL_LIABILITIES")
    out["total_equity"] = _num(bal, "TOTAL_EQUITY")

    # 金融专用（仅金融行有值；EV/PEV 无源字段，不采）
    out["fin_loans"] = _num(main, "GROSSLOANS")
    out["fin_deposits"] = _num(main, "TOTALDEPOSITS")
    out["fin_npl_ratio"] = _num(main, "NONPERLOAN")
    out["fin_car"] = _num(main, "FIRST_ADEQUACY_RATIO")
    out["fin_nbv_life"] = _num(main, "NBV_LIFE")
    out["fin_nbv_rate"] = _num(main, "NBV_RATE")

    # 金融裁剪：金融行清空工业经营/应收存货科目；非金融行清空金融专用列，防源错位污染
    if out["is_financial"]:
        for c in ("accounts_receivable", "inventory", "fixed_asset",
                  "accounts_payable", "sales_cash"):
            out[c] = None
    else:
        for c in ("fin_loans", "fin_deposits", "fin_npl_ratio", "fin_car",
                  "fin_nbv_life", "fin_nbv_rate"):
            out[c] = None

    out["source"] = "EM_DATACENTER"
    out["raw_json"] = ec.raw_json({"main": main, "income": inc,
                                   "balance": bal, "cashflow": cf})
    return out


def main():
    dry = ec.env_flag("FIN_DRY_RUN", True)
    limit = ec.env_int("FIN_LIMIT", 20)
    code = os.environ.get("FIN_CODE", "").strip()
    dates = [d.strip() for d in os.environ.get("FIN_REPORT_DATES", "")
             .replace(" ", "").split(",") if d.strip()]
    source = os.environ.get("FIN_SOURCE", "all").strip().lower()
    keys = ["main", "income", "balance", "cashflow"] if source == "all" else [source]

    # 实测(2026-11-10)：四张财务报表仅接受 REPORT_DATE 服务端过滤；SECURITY_CODE 触发
    # “参数预处理错误”，且不支持双条件拼接；FIN_CODE 改为客户端过滤，不进服务端 filter。
    def filters():
        if dates:
            return ["(REPORT_DATE='%s')" % d for d in dates]
        return [None]

    bucket = {}
    for k in keys:
        n = 0
        kept_code = 0
        for flt in filters():
            rows = ec.dc_fetch(REPORTS[k], extra_filter=flt, max_rows=limit or None)
            n += len(rows)
            rows = rows[:limit] if limit else rows
            for r in rows:
                if code and r.get("SECURITY_CODE") != code:
                    continue
                kept_code += 1
                kk = (r.get("SECURITY_CODE"), ec.to_date(r.get("REPORT_DATE")))
                bucket.setdefault(kk, {})[k] = r
        ec.log(TAG, "report=%s rows=%d code_match=%d dry=%s code=%s dates=%d"
               % (k, n, kept_code, dry, code or "-", len(dates)))

    only_a = ec.env_flag("FIN_A_SHARE_ONLY", True)
    merged = [merge_one(b) for b in bucket.values()]
    pre = len(merged)
    if only_a:
        merged = [m for m in merged if ec.is_a_share(m["code"])]
    full = sum(1 for b in bucket.values()
               if all(x in b for x in ("main", "income", "balance", "cashflow")))
    ec.log(TAG, "merged_groups=%d four_table_full=%d a_share_only=%s kept=%d dropped=%d dry_run=%s"
           % (pre, full, only_a, len(merged), pre - len(merged), dry))

    if dry:
        for m in merged[:3]:
            print(json.dumps({k: v for k, v in m.items() if v not in (None, "")},
                             ensure_ascii=False, default=str))
        ec.log(TAG, "DRY_RUN 未写库；正式流程：备份 -> gap_financial_ddl_review.sql 建表 -> "
                    "灰度 FIN_LIMIT -> 替换为 ON DUPLICATE KEY UPDATE 后放量")
        return

    # —— 写库段：表不存在即中止；ON DUPLICATE KEY UPDATE 刷新修订值（仍需先建表并显式 APPLY）——
    conn = ec.conn()
    cur = conn.cursor()
    if not ec.table_exists(cur, TABLE):
        ec.log(TAG, "目标表 %s 不存在：先执行 gap_financial_ddl_review.sql 建表，已中止写库" % TABLE)
        conn.close()
        return
    upd = [c for c in COLS if c not in ("code", "report_date")]
    n = ec.upsert_many(cur, TABLE, COLS, merged, update_columns=upd)
    conn.commit()
    conn.close()
    ec.log(TAG, "upsert rows=%d (ON DUPLICATE KEY UPDATE; PK code+report_date)" % n)


if __name__ == "__main__":
    main()
