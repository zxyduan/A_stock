#!/bin/sh
# 基础建设第2步(4.1(3)): 仅在新构建的最终应用镜像内只读复测, 不起服务
set -e
echo "[A] python / numpy / talib 版本与函数调用"
python3 -c "import talib,numpy; print('FINAL_TALIB', talib.__version__, 'numpy', numpy.__version__); print('MA=', talib.MA(numpy.array([1.,2.,3.,4.,5.,6.]),3)); print('FUNCS=', len(talib.get_functions()))"

echo "[B] purge 后运行时 C 库是否保留 (libta-lib0 必须在, ta-lib-dev 可不在)"
ldconfig -p | grep -iE "ta_lib|libta" || true
dpkg -l | grep -i ta-lib || true

echo "[C] 应用关键导入链: stockfetch/tablestructure/calculate_indicator (均顶层 import talib)"
cd /data/InStock
PYTHONPATH=/data/InStock python3 -c "import instock.core.stockfetch, instock.core.tablestructure, instock.core.indicator.calculate_indicator; print('IMPORT_CHAIN_OK')"

echo "[D] 关键 Web/作业依赖可导入性"
PYTHONPATH=/data/InStock python3 -c "import tornado, pymysql, sqlalchemy, requests, bokeh, pandas, numpy; print('DEPS_OK', tornado.version)"
echo VERIFY_FINAL_DONE
