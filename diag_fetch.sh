#!/bin/sh
# #4 抓取链路诊断: 容器内项目fetcher/裸requests vs 宿主curl, 东财各host; 纯只读
set +e
echo "===CONTAINER(项目fetcher + 裸requests)==="
docker cp /data/instock/diag_fetch.py InStock:/tmp/diag.py 2>/dev/null
docker exec InStock python3 /tmp/diag.py

echo "===HOST 82.push2 http==="
curl -sS -m10 -o /tmp/h82 -w "code=%{http_code} size=%{size_download} connect=%{time_connect}\n" \
 "http://82.push2.eastmoney.com/api/qt/clist/get?pn=1&pz=5&po=1&np=1&ut=bd1d9ddb04089700cf9c27f6f7426281&fltt=2&invt=2&fid=f12&fs=m:1+t:2&fields=f12,f14,f2,f3"
echo "body:"; head -c 260 /tmp/h82; echo

echo "===HOST push2.eastmoney.com https==="
curl -sS -m10 -o /tmp/hp -w "code=%{http_code} size=%{size_download} connect=%{time_connect}\n" \
 "https://push2.eastmoney.com/api/qt/clist/get?pn=1&pz=5&po=1&np=1&ut=bd1d9ddb04089700cf9c27f6f7426281&fltt=2&invt=2&fid=f12&fs=m:1+t:2&fields=f12,f14,f2,f3"
echo "body:"; head -c 260 /tmp/hp; echo

echo "===DNS resolve (宿主)==="
getent hosts 82.push2.eastmoney.com || echo "82 no-dns"
getent hosts push2.eastmoney.com || echo "push2 no-dns"
echo "===DNS resolve (容器)==="
docker exec InStock python3 -c "import socket; print('82=',socket.gethostbyname('82.push2.eastmoney.com')); print('push2=',socket.gethostbyname('push2.eastmoney.com'))"
echo DIAG_END
