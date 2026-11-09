#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
A股前复权日线历史入库脚本 (自建表 cn_stock_daily_kline)
- 不依赖上游 fetch_stock_hist(规避 pandas 只读就地写 bug), 直接调用底层 she.stock_zh_a_hist
- 幂等: PRIMARY KEY(code,date,adjust) + INSERT IGNORE, 重跑不重复
- 断点续跑: done 清单 kline_done.txt; 失败清单 kline_failed.txt; 进度 kline_progress.txt
环境变量:
  KLINE_START=20210101  KLINE_END=yyyyMMdd(默认今天)  KLINE_ADJUST=qfq
  KLINE_WORKERS=4       KLINE_LIMIT=0(0=全部; 小批量验证可设20)
容器内运行:
  cd /data/InStock && PYTHONPATH=/data/InStock \
  python3 instock/cache/kline_history_loader.py
"""
import os
import sys
import time
import random
import threading
import datetime
import traceback
from concurrent.futures import ThreadPoolExecutor, as_completed

import pymysql
import instock.core.crawling.stock_hist_em as she

BASE = "/data/InStock/instock/cache"
TABLE = "cn_stock_daily_kline"
DB = dict(
    host=os.environ.get("db_host", "InStockDbService"),
    user=os.environ.get("db_user", "root"),
    password=os.environ.get("db_password", "root"),
    database=os.environ.get("db_database", "instockdb"),
    charset="utf8mb4",
    autocommit=False,
)
ADJUST = os.environ.get("KLINE_ADJUST", "qfq")
START = os.environ.get("KLINE_START", "20210101")
END = os.environ.get("KLINE_END", datetime.date.today().strftime("%Y%m%d"))
WORKERS = int(os.environ.get("KLINE_WORKERS", "4"))
LIMIT = int(os.environ.get("KLINE_LIMIT", "0"))

DONE_F = os.path.join(BASE, "kline_done.txt")
FAIL_F = os.path.join(BASE, "kline_failed.txt")
PROG_F = os.path.join(BASE, "kline_progress.txt")

CN2EN = {
    "日期": "date", "开盘": "open", "收盘": "close", "最高": "high", "最低": "low",
    "成交量": "volume", "成交额": "amount", "振幅": "amplitude", "涨跌幅": "p_change",
    "涨跌额": "change_amount", "换手率": "turnover",
}
LOCK = threading.Lock()
STAT = {"done": 0, "rows": 0, "fail": 0}


def log(msg):
    line = "%s %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    print(line, flush=True)
    with open(PROG_F, "a", encoding="utf-8") as f:
        f.write(line + "\n")


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
        `code` varchar(10) NOT NULL COMMENT '证券代码',
        `name` varchar(32) DEFAULT NULL COMMENT '证券名称',
        `date` date NOT NULL COMMENT '交易日',
        `adjust` varchar(4) NOT NULL DEFAULT 'qfq' COMMENT '复权 qfq/hfq/none',
        `open` float DEFAULT NULL, `close` float DEFAULT NULL,
        `high` float DEFAULT NULL, `low` float DEFAULT NULL,
        `volume` double DEFAULT NULL COMMENT '成交量股',
        `amount` double DEFAULT NULL COMMENT '成交额元',
        `amplitude` float DEFAULT NULL COMMENT '振幅',
        `p_change` float DEFAULT NULL COMMENT '涨跌幅',
        `change_amount` float DEFAULT NULL COMMENT '涨跌额',
        `turnover` float DEFAULT NULL COMMENT '换手率',
        PRIMARY KEY (`code`,`date`,`adjust`),
        KEY `idx_date` (`date`),
        KEY `idx_name_code` (`code`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='A股日线历史自建'"""
    )
    conn.commit()
    conn.close()


def code_pool():
    """优先取 cn_stock_spot 最新股票池(code,name); 表空则回退实时全量。"""
    conn = pymysql.connect(**DB)
    cur = conn.cursor()
    cur.execute(
        "SELECT code, MAX(name) AS name FROM cn_stock_spot GROUP BY code ORDER BY code"
    )
    rows = cur.fetchall()
    conn.close()
    if rows:
        return [(r[0], r[1] or "") for r in rows]
    log("cn_stock_spot 为空, 改用实时全量列表")
    spot = she.stock_zh_a_spot_em()
    out = []
    for _, r in spot.iterrows():
        out.append((str(r.get("代码", "")), str(r.get("名称", ""))))
    return out


def insert_rows(code, name, rows):
    if not rows:
        return 0
    conn = pymysql.connect(**DB)
    cur = conn.cursor()
    sql = (
        "INSERT IGNORE INTO `%s` "
        "(code,name,date,adjust,open,close,high,low,volume,amount,amplitude,p_change,change_amount,turnover) "
        "VALUES (%%s,%%s,%%s,%%s,%%s,%%s,%%s,%%s,%%s,%%s,%%s,%%s,%%s,%%s)" % TABLE
    )
    cur.executemany(sql, rows)
    n = cur.rowcount
    conn.commit()
    conn.close()
    return n


def fetch_one(code, name):
    df = she.stock_zh_a_hist(
        symbol=code, period="daily", start_date=START, end_date=END, adjust=ADJUST
    )
    if df is None or len(df) == 0:
        return 0
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
    return insert_rows(code, name, rows)


def main():
    os.makedirs(BASE, exist_ok=True)
    ensure_table()
    pool = code_pool()
    if LIMIT and LIMIT > 0:
        pool = pool[:LIMIT]
    done = set()
    if os.path.exists(DONE_F):
        done = set(x.strip() for x in open(DONE_F, encoding="utf-8") if x.strip())
    todo = [c for c in pool if c[0] not in done]
    log("START total_pool=%d todo=%d workers=%d start=%s end=%s adjust=%s"
        % (len(pool), len(todo), WORKERS, START, END, ADJUST))

    def task(item):
        code, name = item
        err = None
        for _ in range(2):
            try:
                n = fetch_one(code, name)
                with LOCK:
                    STAT["done"] += 1
                    STAT["rows"] += n
                    with open(DONE_F, "a", encoding="utf-8") as f:
                        f.write(code + "\n")
                    if STAT["done"] % 10 == 0:
                        log("progress done=%d rows=%d fail=%d last=%s"
                            % (STAT["done"], STAT["rows"], STAT["fail"], code))
                time.sleep(random.uniform(0.05, 0.20))
                return
            except Exception as e:
                err = repr(e)
                time.sleep(random.uniform(1.0, 2.5))
        with LOCK:
            STAT["fail"] += 1
            with open(FAIL_F, "a", encoding="utf-8") as f:
                f.write("%s\t%s\n" % (code, err))

    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = [ex.submit(task, it) for it in todo]
        for fu in as_completed(futs):
            try:
                fu.result()
            except Exception:
                traceback.print_exc()
    log("ALL_DONE done=%d rows_inserted=%d fail=%d pool=%d"
        % (STAT["done"], STAT["rows"], STAT["fail"], len(pool)))


if __name__ == "__main__":
    main()
