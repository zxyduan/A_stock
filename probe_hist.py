import os, sys, glob
sys.path.insert(0, '/data/InStock')
import instock.core.crawling.stock_hist_em as she
import instock.core.crawling.fund_etf_em as fee
import instock.core.stockfetch as stf
import instock.lib.trade_time as trd

print("== 1 raw stock hist 600519 via crawling layer ==")
try:
    d = she.stock_zh_a_hist(symbol='600519', period='daily', start_date='20230101', adjust='qfq')
    print("shape=", None if d is None else d.shape)
    if d is not None and len(d):
        print("cols=", list(d.columns))
        print("date_range=", d.index.min(), "->", d.index.max(), "rows=", len(d))
except Exception as e:
    print("RAW_STOCK_ERR:", repr(e))

print("== 2 raw ETF hist 510300 via crawling layer ==")
try:
    e = fee.fund_etf_hist_em(symbol='510300', period='daily', start_date='20230101', adjust='qfq')
    print("shape=", None if e is None else e.shape)
    if e is not None and len(e):
        print("date_range=", e.index.min(), "->", e.index.max(), "rows=", len(e))
except Exception as ex:
    print("RAW_ETF_ERR:", repr(ex))

print("== 3 stock_hist_cache (pickle cache layer, no in-place ROC) ==")
try:
    c = stf.stock_hist_cache('600519', '20230101', None, True, 'qfq')
    print("cache_shape=", None if c is None else c.shape)
except Exception as ex:
    print("CACHE_ERR:", repr(ex))

print("== 4 fetch_stock_hist (post-process incl. in-place p_change) ==")
try:
    h = stf.fetch_stock_hist(('2026-11-06', '600519'))
    print("fetch_hist_type=", type(h).__name__, "shape=", None if h is None else h.shape)
except Exception as ex:
    print("FETCH_HIST_ERR:", repr(ex))

print("== 5 cache dir on mounted volume ==")
base = '/data/InStock/instock/cache/hist'
try:
    files = glob.glob(base + '/**/*.gzip.pickle', recursive=True)
    print("pickle_count=", len(files))
    if files:
        sizes = sum(os.path.getsize(f) for f in files)
        print("pickle_bytes=", sizes)
        print("sample=", files[:3])
except Exception as ex:
    print("CACHE_DIR_ERR:", repr(ex))

print("== 6 default interval for '2026-11-06' ==")
print(trd.get_trade_hist_interval('2026-11-06'))
print("HISTPROBE_DONE")
