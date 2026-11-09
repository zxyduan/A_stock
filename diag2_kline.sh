#!/bin/sh
set +e
echo "== kline_history.log =="
cat /data/instock/app/cache/kline_history.log
echo "== progress tail =="
tail -8 /data/instock/app/cache/kline_progress.txt
echo "== docker top InStock (host-side process list) =="
docker top InStock
echo DIAG2_DONE
