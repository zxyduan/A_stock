import sys, traceback
sys.path.insert(0, '/data/InStock')
import instock.core.eastmoney_fetcher as ef

orig = ef.eastmoney_fetcher.make_request

def patched(self, url, params=None, retry=3, timeout=10):
    r = orig(self, url, params=params, retry=retry, timeout=timeout)
    print("REQ", url)
    print("  params=", params)
    print("  -> status=", r.status_code, "len=", len(r.content),
          "ctype=", r.headers.get("Content-Type"),
          "content-encoding=", r.headers.get("Content-Encoding"),
          "bodyhead=", repr(r.text[:220]))
    return r

ef.eastmoney_fetcher.make_request = patched

import instock.core.crawling.stock_hist_em as she
print("==== stock_zh_a_spot_em ====")
try:
    d = she.stock_zh_a_spot_em()
    print("rows=", None if d is None else len(d))
except Exception:
    traceback.print_exc()
print("PATCH_REPRO_END")
