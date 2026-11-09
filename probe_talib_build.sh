#!/bin/sh
# 在与构建基础完全一致的 python:3.11-slim-bookworm 中, 复刻正式 Dockerfile 将采用的 TA-Lib 方案:
# Debian 预编译 C 库(deb, 免 autotools ./configure) + requirements 指定绑定 TA-Lib==0.6.8(现编译, 匹配 numpy2)
# 仅验证, 不提交; RESULT_TALIB_OK 才允许据此改 Dockerfile 正式 build。
set -eu
export PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/
export PIP_DISABLE_PIP_VERSION_CHECK=1

echo "[0] python runtime:"
python3 -c "import sys,sysconfig;print(sys.version.split()[0], sysconfig.get_paths()['include'])"

echo "[1] apt: build tools (对齐 Dockerfile gcc/make/python3-dev/pkg-config/curl)"
printf 'deb https://mirrors.aliyun.com/debian bookworm main\ndeb https://mirrors.aliyun.com/debian-security bookworm-security main\n' > /etc/apt/sources.list
rm -f /etc/apt/sources.list.d/*.sources
apt-get update -qq
apt-get install -y -qq gcc make python3-dev pkg-config curl ca-certificates >/tmp/apt.log 2>&1 || { echo APT_FAIL; tail -25 /tmp/apt.log; exit 1; }
echo "build tools installed"

echo "[2] download TA-Lib C library debs (libta-lib0 + ta-lib-dev)"
cd /tmp
curl -fSL --retry 2 -o libta.deb https://mirrors.aliyun.com/debian/pool/main/t/ta-lib/libta-lib0_0.7.1-1_amd64.deb
curl -fSL --retry 2 -o talib-dev.deb https://mirrors.aliyun.com/debian/pool/main/t/ta-lib/ta-lib-dev_0.7.1-1_amd64.deb
ls -l libta.deb talib-dev.deb
dpkg -i libta.deb talib-dev.deb || apt-get -f install -y -qq
ldconfig
echo "--- shared libs:"; ldconfig -p | grep -i ta_lib || true
echo "--- headers:"; ls /usr/include/ta-lib 2>/dev/null | head -8 || true

echo "[3] numpy==2.4.1 + TA-Lib==0.6.8 binding (sdist compiled here)"
pip install -q numpy==2.4.1
pip install -q TA-Lib==0.6.8

echo "[4] import + function self-test"
python3 - <<'PY'
import talib, numpy
print("TALIB_OK", talib.__version__, "numpy", numpy.__version__)
arr = numpy.array([1.0,2.0,3.0,4.0,5.0,6.0])
print("MA=", talib.MA(arr, timeperiod=3))
print("FUNC_COUNT=", len(talib.get_functions()))
PY
echo RESULT_TALIB_OK
