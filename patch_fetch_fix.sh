#!/bin/sh
# #4 抓取 br 解压bug持久化修复: 从运行容器取出 fetcher 文件, 仅把 Accept-Encoding 一行降级为 gzip,deflate
set -e
mkdir -p /data/instock/patches
docker cp InStock:/data/InStock/instock/core/eastmoney_fetcher.py /data/instock/patches/eastmoney_fetcher.py
sed -i "s|'Accept-Encoding': 'gzip, deflate, br, zstd'|'Accept-Encoding': 'gzip, deflate'|" /data/instock/patches/eastmoney_fetcher.py

echo "=== patched Accept-Encoding line ==="
grep -n "Accept-Encoding" /data/instock/patches/eastmoney_fetcher.py

echo "=== residual 'br, zstd' (应输出 no residual) ==="
if grep -n "br, zstd" /data/instock/patches/eastmoney_fetcher.py; then
  echo "RESIDUAL_FOUND"
else
  echo "no br,zstd residual"
fi
echo PATCH_GEN_DONE
