#!/bin/sh
# 基础建设第1步: 后台重建 mayanghua/instock:latest; 结果写入 build_fixed.log / build_fixed.exit
cd /data/instock/build
rm -f /data/instock/build_fixed.exit /data/instock/build_fixed.log
nohup sh -c 'docker build --network=host -t mayanghua/instock:latest . > /data/instock/build_fixed.log 2>&1; echo BUILD_EXIT=$? > /data/instock/build_fixed.exit' >/dev/null 2>&1 &
echo "build-launched pid=$!"
sleep 4
echo "=== head of build log ==="
tail -25 /data/instock/build_fixed.log 2>/dev/null || echo "(log not yet written)"
