#!/bin/sh
set +e
docker exec InStock sh -c 'cd /data/InStock && PYTHONPATH=/data/InStock python3 instock/cache/probe_one.py'
echo PROBE_ONE_DONE
