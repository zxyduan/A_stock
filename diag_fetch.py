import sys, os, requests
sys.path.insert(0, '/data/InStock')
from instock.core.eastmoney_fetcher import eastmoney_fetcher

f = eastmoney_fetcher()
print('PROXIES=', f.proxies)

params = {
    "pn": 1, "pz": 5, "po": "1", "np": "1",
    "ut": "bd1d9ddb04089700cf9c27f6f7426281",
    "fltt": "2", "invt": "2", "fid": "f12",
    "fs": "m:0 t:6,m:0 t:80,m:1 t:2,m:1 t:23,m:0 t:81 s:2048",
    "fields": "f12,f14,f2,f3",
}
targets = [
    ("fetcher_82_http", "http://82.push2.eastmoney.com/api/qt/clist/get"),
    ("fetcher_88_http", "http://88.push2.eastmoney.com/api/qt/clist/get"),
    ("fetcher_push2_https", "https://push2.eastmoney.com/api/qt/clist/get"),
]
for name, u in targets:
    try:
        r = f.make_request(u, params=params)
        print(f"{name} status={r.status_code} len={len(r.content)} ctype={r.headers.get('Content-Type')}")
        print("  body=", r.text[:260].replace("\n", " "))
    except Exception as e:
        print(f"{name} EXC={type(e).__name__}: {str(e)[:220]}")

print("--- raw requests (no project cookie/session) ---")
for name, u in [("raw_82_http", "http://82.push2.eastmoney.com/api/qt/clist/get"),
                ("raw_push2_https", "https://push2.eastmoney.com/api/qt/clist/get")]:
    try:
        r = requests.get(u, params=params, timeout=10)
        print(f"{name} status={r.status_code} len={len(r.content)} body={r.text[:220].replace(chr(10),' ')}")
    except Exception as e:
        print(f"{name} EXC={type(e).__name__}: {str(e)[:220]}")
