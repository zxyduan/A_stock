#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
em_common.py —— 东财缺口补全采集器公共库（P1：#3 分红 / #6 宽基指数 / #8a 解禁）

设计红线（与既有 kline_history_loader / indicators_history_backfill 一致）：
  1. 只做“只读拉取 + 默认 DRY_RUN”；不自动建表、不 DELETE/UPDATE、不改 cron、不重启。
  2. 实写必须显式 *_DRY_RUN=0，且目标表已由 gap_ddl_review.sql 评审创建；否则中止写库。
  3. 写库一律 INSERT IGNORE，幂等可重跑；断点/进度文件落 CACHE_DIR（运行副本，不入库）。
  4. 不引入 akshare；仅依赖容器已具备的 pymysql + requests。
  5. 东财 datacenter 网关与 push2his kline 端点均已在 2026-11-10 只读探针验证可达。
"""
import os
import json
import re
import time
import requests
import pymysql

DB = dict(
    host=os.environ.get("db_host", "InStockDbService"),
    user=os.environ.get("db_user", "root"),
    password=os.environ.get("db_password", "root"),
    database=os.environ.get("db_database", "instockdb"),
    charset="utf8mb4",
    autocommit=False,
)
CACHE = os.environ.get("CACHE_DIR", "/data/InStock/instock/cache")
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36"
DC_URL = "https://datacenter-web.eastmoney.com/api/data/v1/get"
KLINE_URL = "https://push2his.eastmoney.com/api/qt/stock/kline/get"


def conn():
    return pymysql.connect(**DB)


def env_int(name, default):
    try:
        return int(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


def env_flag(name, default=False):
    v = os.environ.get(name)
    if v is None:
        return default
    return v.strip().lower() in ("1", "true", "yes", "on")


def fnum(v):
    """NaN/Inf/None -> None；其余转 float，避免把脏值写入数值列。"""
    try:
        if v is None:
            return None
        x = float(v)
        if x != x:  # NaN
            return None
        if x in (float("inf"), float("-inf")):
            return None
        return x
    except (TypeError, ValueError):
        return None


def to_date(v):
    """'2024-10-25 00:00:00' -> '2024-10-25'；空值 -> None。"""
    if v is None:
        return None
    s = str(v).strip()
    if not s:
        return None
    return s[:10]


# A股代码白名单（沪深主板/中小/创业板/科创板普通股，6位）；排除北交所(920=.BJ、8xx/4xx)、
# 老三板/新三板(.NQ,4/8开头)、B股(900/200)、科创板CDR(689,如689009九号公司,默认排除)、占位代码。
# 2026-11-10 依据库内东财原始 SECUCODE 后缀实测校准：302132.SZ=深创业板普通股 -> 纳入302；
# 689009.SH=科创CDR非普通股 -> 不纳入；920xxx.BJ=北交所 -> 排除。市场过滤默认开启、可被采集器关闭。
_A_SHARE_RE = re.compile(r"^(?:000|001|002|003|300|301|302|600|601|603|605|688)\d{3}$")


def is_a_share(code):
    """True=沪深A股普通股(主板/中小/创业板/科创板)；剔除北交所920(.BJ)、科创CDR 689、三板/B股/占位。"""
    return bool(code) and bool(_A_SHARE_RE.match(str(code).strip()))


def session():
    s = requests.Session()
    # 与 patches/eastmoney_fetcher.py 一致：只声明 gzip,deflate，避免 br/zstd 无解码库报错
    s.headers.update({
        "User-Agent": UA,
        "Accept-Encoding": "gzip, deflate",
        "Referer": "https://data.eastmoney.com/",
    })
    return s


def dc_fetch(report_name, extra_filter=None, max_pages=100, page_size=500, sleep=0.35, max_rows=None):
    """
    datacenter 报表网关分页拉取，返回 list[dict]。
    不传排序字段（不同报表排序列名不同，避免“排序列不存在”报错）。
    max_rows 用于干跑/灰度：累计达到即提前停止，避免拉全历史。
    """
    s = session()
    rows = []
    for page in range(1, max_pages + 1):
        params = {
            "reportName": report_name,
            "columns": "ALL",
            "pageSize": page_size,
            "pageNumber": page,
            "source": "WEB",
            "client": "WEB",
        }
        if extra_filter:
            params["filter"] = extra_filter
        j = None
        for attempt in range(3):
            try:
                r = s.get(DC_URL, params=params, timeout=12)
                r.raise_for_status()
                j = r.json()
                break
            except Exception as e:
                if attempt == 2:
                    raise
                time.sleep(1.5 * (attempt + 1))
        if not j or not j.get("success"):
            raise RuntimeError("dc %s success=false: %s" % (report_name, (j or {}).get("message")))
        res = j.get("result") or {}
        data = res.get("data") or []
        rows.extend(data)
        if max_rows and len(rows) >= max_rows:
            break
        pages = int(res.get("pages") or 1)
        if page >= pages or not data:
            break
        time.sleep(sleep)
    return rows


def kline_index(secid, beg, end, s=None):
    """指数日K：secid 沪市 1.<code> / 深市 0.<code>；返回 (name, [row,...])。"""
    s = s or session()
    params = {
        "secid": secid,
        "fields1": "f1,f2,f3,f4,f5,f6",
        "fields2": "f51,f52,f53,f54,f55,f56,f57,f58",
        "klt": "101", "fqt": "1", "beg": beg, "end": end,
    }
    r = s.get(KLINE_URL, params=params, timeout=12)
    r.raise_for_status()
    j = r.json()
    data = j.get("data") or {}
    out = []
    for line in (data.get("klines") or []):
        p = line.split(",")
        if len(p) < 7:
            continue
        out.append({
            "date": p[0],
            "open": fnum(p[1]), "close": fnum(p[2]),
            "high": fnum(p[3]), "low": fnum(p[4]),
            "volume": fnum(p[5]), "amount": fnum(p[6]),
        })
    return data.get("name"), out


def table_exists(cur, table):
    cur.execute(
        "SELECT 1 FROM information_schema.tables WHERE table_schema=%s AND table_name=%s",
        (DB["database"], table),
    )
    return cur.fetchone() is not None


def insert_ignore(cur, table, columns, rows):
    if not rows:
        return 0
    cols = ",".join("`%s`" % c for c in columns)
    ph = ",".join(["%s"] * len(columns))
    sql = "INSERT IGNORE INTO `%s` (%s) VALUES (%s)" % (table, cols, ph)
    cur.executemany(sql, [tuple(r.get(c) for c in columns) for r in rows])
    return cur.rowcount


# 主键列保护名单：upsert 刷新普通列，绝不回写主键（调用方也可自行传 update_columns 收窄）
_PK_GUARD = ("code", "report_date", "date", "index_code", "event_date")


def upsert_many(cur, table, columns, rows, update_columns=None):
    """ON DUPLICATE KEY UPDATE：同主键存在则刷新普通列（适合财报修订/补录场景）。

    返回处理条数 len(rows)，不依赖 MySQL 1(insert)/2(update) 的 rowcount 语义差异。
    update_columns 缺省=全部 columns 剔除 _PK_GUARD；主键列始终不出现在 SET 子句。
    与 insert_ignore 并列存在：事件/快照类幂等去重仍用 IGNORE，季度修订类用 upsert。
    """
    if not rows:
        return 0
    cols = list(columns)
    if update_columns is None:
        update_columns = [c for c in cols if c not in _PK_GUARD]
    upd = [c for c in update_columns if c not in _PK_GUARD]
    col_sql = ",".join("`%s`" % c for c in cols)
    ph = ",".join(["%s"] * len(cols))
    set_sql = ",".join("`%s`=VALUES(`%s`)" % (c, c) for c in upd)
    sql = "INSERT INTO `%s` (%s) VALUES (%s) ON DUPLICATE KEY UPDATE %s" % (
        table, col_sql, ph, set_sql)
    cur.executemany(sql, [tuple(r.get(c) for c in cols) for r in rows])
    return len(rows)


def log(tag, msg):
    line = "%s [%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), tag, msg)
    print(line, flush=True)
    try:
        os.makedirs(CACHE, exist_ok=True)
        with open(os.path.join(CACHE, tag + "_progress.txt"), "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def raw_json(x):
    try:
        return json.dumps(x, ensure_ascii=False, default=str)
    except Exception:
        return None
