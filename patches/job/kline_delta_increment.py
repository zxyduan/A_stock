#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
盘后增量补抓 A 股前复权日线（与全量回填 loader 解耦）。

设计：
- 不读取/不写入全量回填的 kline_done.txt，因此每次都按窗口遍历股票池；
- 落库使用 INSERT IGNORE + 主键(code,date,adjust)，窗口内已存在的交易日自动跳过，
  只插入窗口内新增交易日（例如补到最新收盘日），重跑幂等、不重复。
- 数据源直接调用 instock.core.crawling.stock_hist_em.she.stock_zh_a_hist，
  绕开有 pandas CoW 只读就地写问题的 fetch_stock_hist。

环境变量（docker exec -e 传入）：
  KLINE_START=yyyyMMdd  窗口起（缺省=KLINE_END）
  KLINE_END=yyyyMMdd    窗口止（缺省=今天）
  KLINE_ADJUST=qfq      复权口径
  KLINE_WORKERS=4       并发线程（2 核主机建议 4）
  KLINE_LIMIT=0         >0 时只取前 N 只（小批实测用，0=全池）
"""
import os
import time
import random
import datetime
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

import pymysql
import instock.core.crawling.stock_hist_em as she

DB = dict(
    host=os.environ.get("db_host", "InStockDbService"),
    user=os.environ.get("db_user", "root"),
    password=os.environ.get("db_password", "root"),
    database=os.environ.get("db_database", "instockdb"),
    charset="utf8mb4",
    autocommit=False,
)
ADJUST = os.environ.get("KLINE_ADJUST", "qfq")
END = os.environ.get("KLINE_END", datetime.date.today().strftime("%Y%m%d"))
START = os.environ.get("KLINE_START", END)
WORKERS = int(os.environ.get("KLINE_WORKERS", "4"))
LIMIT = int(os.environ.get("KLINE_LIMIT", "0"))

TABLE = "cn_stock_daily_kline"
CN2EN = {
    "日期": "date", "开盘": "open", "收盘": "close", "最高": "high", "最低": "low",
    "成交量": "volume", "成交额": "amount", "振幅": "amplitude", "涨跌幅": "p_change",
    "涨跌额": "change_amount", "换手率": "turnover",
}
LOCK = threading.Lock()
STAT = {"ok": 0, "fail": 0, "rows": 0, "fail_codes": []}


def log(msg):
    print("%s %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg), flush=True)


def _f(v):
    try:
        if v is None:
            return None
        x = float(v)
        if x != x:  # NaN
            return None
        return x
    except Exception:
        return None


def ensure_table():
    conn = pymysql.connect(**DB)
    cur = conn.cursor()
    cur.execute(
        f"""CREATE TABLE IF NOT EXISTS `{TABLE}` (
        `code` varchar(10) NOT NULL, `name` varchar(32) DEFAULT NULL,
        `date` date NOT NULL, `adjust` varchar(4) NOT NULL DEFAULT 'qfq',
        `open` float DEFAULT NULL, `close` float DEFAULT NULL,
        `high` float DEFAULT NULL, `low` float DEFAULT NULL,
        `volume` double DEFAULT NULL, `amount` double DEFAULT NULL,
        `amplitude` float DEFAULT NULL, `p_change` float DEFAULT NULL,
        `change_amount` float DEFAULT NULL, `turnover` float DEFAULT NULL,
        PRIMARY KEY (`code`,`date`,`adjust`), KEY `idx_date` (`date`), KEY `idx_name_code` (`code`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"""
    )
    conn.commit(); conn.close()


def count_rows():
    conn = pymysql.connect(**DB); cur = conn.cursor()
    cur.execute(f"SELECT COUNT(*) FROM `{TABLE}` WHERE adjust=%s", (ADJUST,))
    n = cur.fetchone()[0]; conn.close(); return n


def stock_pool():
    conn = pymysql.connect(**DB); cur = conn.cursor()
    cur.execute(
        "SELECT code, MAX(name) AS name FROM cn_stock_spot GROUP BY code ORDER BY code")
    rows = cur.fetchall(); conn.close()
    return [(r[0], r[1] or "") for r in rows]


def upsert_rows(code, name, rows):
    if not rows:
        return 0
    conn = pymysql.connect(**DB); cur = conn.cursor()
    sql = (
        "INSERT IGNORE INTO `%s` "
        "(code,name,date,adjust,open,close,high,low,volume,amount,amplitude,p_change,change_amount,turnover) "
        "VALUES (%%s,%%s,%%s,%%s,%%s,%%s,%%s,%%s,%%s,%%s,%%s,%%s,%%s,%%s)" % TABLE
    )
    cur.executemany(sql, rows)
    n = cur.rowcount
    conn.commit(); conn.close()
    return n


def work(item):
    code, name = item
    try:
        df = she.stock_zh_a_hist(symbol=code, period="daily",
                                 start_date=START, end_date=END, adjust=ADJUST)
        if df is None or len(df) == 0:
            with LOCK:
                STAT["fail"] += 1; STAT["fail_codes"].append(code + ":empty")
            return
        df = df.rename(columns=CN2EN)
        rows = []
        for r in df.itertuples(index=False):
            rd = dict(zip(df.columns, r))
            rows.append((
                code, name, str(rd["date"])[:10], ADJUST,
                _f(rd.get("open")), _f(rd.get("close")), _f(rd.get("high")), _f(rd.get("low")),
                _f(rd.get("volume")), _f(rd.get("amount")), _f(rd.get("amplitude")),
                _f(rd.get("p_change")), _f(rd.get("change_amount")), _f(rd.get("turnover")),
            ))
        n = upsert_rows(code, name, rows)
        with LOCK:
            STAT["ok"] += 1; STAT["rows"] += n
        time.sleep(random.uniform(0.05, 0.18))
    except Exception as e:
        with LOCK:
            STAT["fail"] += 1; STAT["fail_codes"].append("%s:%s" % (code, repr(e)[:160]))


def main():
    ensure_table()
    before = count_rows()
    pool = stock_pool()
    if LIMIT and LIMIT > 0:
        pool = pool[:LIMIT]
    log("DELTA_START window=%s..%s adjust=%s workers=%d pool=%d table_before=%d"
        % (START, END, ADJUST, WORKERS, len(pool), before))
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = [ex.submit(work, it) for it in pool]
        done = 0
        for fu in as_completed(futs):
            try:
                fu.result()
            except Exception:
                pass
            done += 1
            if done % 100 == 0:
                log("progress processed=%d ok=%d fail=%d rows=%d"
                    % (done, STAT["ok"], STAT["fail"], STAT["rows"]))
    after = count_rows()
    log("DELTA_DONE ok=%d fail=%d rows_inserted=%d table_before=%d table_after=%d delta=%d"
        % (STAT["ok"], STAT["fail"], STAT["rows"], before, after, after - before))
    if STAT["fail_codes"]:
        log("fail_codes_sample=" + " | ".join(STAT["fail_codes"][:15]))


if __name__ == "__main__":
    main()
