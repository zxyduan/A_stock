#!/bin/sh
# 步骤探测: ta-lib-bin manylinux 预编译 wheel 是否直接提供可用的 talib 模块(免编译/免系统deb)
set -e
export DEBIAN_FRONTEND=noninteractive
echo "[1/2] pip install ta-lib-bin==0.4.26 (cp311 manylinux wheel)"
pip install ta-lib-bin==0.4.26
echo "[2/2] import + function self-test"
python3 -c "import talib; print('WHEEL_TALIB_OK', talib.__version__); print('MA=', talib.MA([1.0,2.0,3.0,4.0,5.0,6.0], timeperiod=3))"
echo WHEEL_PROBE_DONE_OK
