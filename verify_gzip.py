import sys
sys.path.insert(0, '/data/InStock')
import instock.core.eastmoney_fetcher as ef

f = ef.eastmoney_fetcher()
# 验证修复B: 去掉 br/zstd, 仅允许 gzip,deflate
f.session.headers['Accept-Encoding'] = 'gzip, deflate'

params = {
    "pn": 1, "pz": 50, "po": "1", "np": "1",
    "ut": "bd1d9ddb04089700cf9c27f6f7426281",
    "fltt": "2", "invt": "2", "fid": "f12",
    "fs": "m:0 t:6,m:0 t:80,m:1 t:2,m:1 t:23,m:0 t:81 s:2048",
    "fields": "f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f14,f15,f16,f17,f18,f20,f21,f22,f23,f24,f25,f26,f37,f38,f39,f40,f41,f45,f46,f48,f49,f57,f61,f100,f112,f113,f114,f115,f221",
    "_": "1623833739532",
}
r = f.make_request("http://82.push2.eastmoney.com/api/qt/clist/get", params=params)
print("ce=", r.headers.get("Content-Encoding"), "status=", r.status_code, "len=", len(r.content))
j = r.json()
print("TOTAL=", j["data"]["total"], "SAMPLE=", j["data"]["diff"][0])
print("GZIP_FIX_OK")
