#!/bin/sh
# 应用 br 解压修复: 校验编排 -> 仅重建 app 容器(DB不动) -> 验证挂载/运行时/Web
set +e
cd /data/instock
echo "=== CONFIG_VALIDATE ==="
docker compose config --quiet && echo CONFIG_OK || echo CONFIG_BAD
echo "=== UP_APP ==="
docker compose up -d instock
sleep 10
echo "=== PS ==="
docker compose ps
echo "=== MOUNTED_PATCH_IN_CONTAINER ==="
docker exec InStock grep -n "Accept-Encoding" /data/InStock/instock/core/eastmoney_fetcher.py
echo "=== RUNTIME_CHECK(header+talib) ==="
docker exec InStock sh -lc "cd /data/InStock && PYTHONPATH=/data/InStock python3 -c 'import talib; from instock.core.eastmoney_fetcher import eastmoney_fetcher; f=eastmoney_fetcher(); print(\"HEADER=\"+f.session.headers[\"Accept-Encoding\"]+\" TALIB=\"+talib.__version__)'"
echo "=== WEB_9988 ==="
curl -sS -m8 -o /dev/null -w "web_code=%{http_code}\n" http://127.0.0.1:9988/instock/
echo APPLY_FIX_DONE
