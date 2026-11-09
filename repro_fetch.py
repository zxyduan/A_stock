import sys, traceback
sys.path.insert(0, '/data/InStock')
import instock.core.crawling.stock_hist_em as she
import instock.core.crawling.fund_etf_em as fee

for name, fn in [("stock_zh_a_spot_em", she.stock_zh_a_spot_em),
                 ("fund_etf_spot_em", fee.fund_etf_spot_em)]:
    print("==== call", name)
    try:
        d = fn()
        print("OK rows=", None if d is None else len(d),
              "cols=", None if d is None else list(d.columns)[:6])
    except Exception:
        traceback.print_exc()

# 底层单页探测: 打印状态码/长度/响应头/正文前300, 区分空body与分页问题
from instock.core.eastmoney_fetcher import eastmoney_fetcher
f = eastmoney_fetcher()
params = {"pn": 1, "pz": 50, "po": "1", "np": "1",
          "ut": "bd1d9ddb04089700cf9c27f6f7426281", "fltt": "2", "invt": "2", "fid": "f12",
          "fs": "m:0 t:6,m:0 t:80,m:1 t:2,m:1 t:23,m:0 t:81 s:2048",
          "fields": "f2,f3,f12,f14"}
for u in ["http://82.push2.eastmoney.com/api/qt/clist/get",
          "http://88.push2.eastmoney.com/api/qt/clist/get"]:
    try:
        r = f.make_request(u, params=params)
        print("RAW", u, "status=", r.status_code, "len=", len(r.content),
              "ctype=", r.headers.get("Content-Type"), "body=", r.text[:300].replace("\n", " "))
    except Exception:
        traceback.print_exc()
print("REPRO_END")
