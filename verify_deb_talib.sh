#!/bin/sh
# 步骤1前置：在干净 bookworm 容器内验证 "Debian 官方 deb C库 + pip TA-Lib 绑定" 组合可用，
# 锁定版本后再固化进 Dockerfile 重建，避免重建后 ABI 不兼容返工。
set -e
export DEBIAN_FRONTEND=noninteractive
echo "[1/5] apt mirror + build tools"
sed -i -e "s@http://deb.debian.org/debian-security@https://mirrors.aliyun.com/debian-security@g" \
       -e "s@http://deb.debian.org/debian@https://mirrors.aliyun.com/debian@g" \
       /etc/apt/sources.list.d/debian.sources
apt-get update -qq
apt-get install -y -qq gcc make python3-dev pkg-config
echo "[2/5] install TA-Lib deb (C lib + headers)"
apt-get install -y --no-install-recommends \
  https://mirrors.aliyun.com/debian/pool/main/t/ta-lib/libta-lib0_0.7.1-1_amd64.deb \
  https://mirrors.aliyun.com/debian/pool/main/t/ta-lib/ta-lib-dev_0.7.1-1_amd64.deb
ldconfig
ldconfig -p | grep ta_lib
echo "[3/5] pip TA-Lib binding (latest)"
pip install TA-Lib
echo "[4/5] import + function self-test"
python3 -c "import talib; print('TALIB_IMPORT_OK', talib.__version__); print('MA=', talib.MA([1.0,2.0,3.0,4.0,5.0,6.0], timeperiod=3))"
echo "[5/5] PROBE_DONE_OK"
