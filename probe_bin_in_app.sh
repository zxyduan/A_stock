#!/bin/sh
# 在最终应用镜像 mayanghua/instock:latest(已含numpy/pandas)上, 用阿里云PyPI源探测 ta-lib-bin wheel
export PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/
export PIP_DISABLE_PIP_VERSION_CHECK=1

echo "[0] 现有依赖基线:"
python3 -c "import numpy,pandas;print('numpy',numpy.__version__,'pandas',pandas.__version__)"

echo "[1] pip install ta-lib-bin==0.4.26"
pip install ta-lib-bin==0.4.26
echo "[1-rc] pip exit=$?"

echo "[2] import talib + 函数调用自测"
python3 -c "import talib; print('BIN_TALIB_OK', getattr(talib,'__version__','n/a')); print('MA=', talib.MA([1.0,2.0,3.0,4.0,5.0,6.0], timeperiod=3))"
echo "[2-rc] import exit=$?"

echo "[3] 该包实际提供的顶层命名空间:"
python3 -c "import importlib,glob,os; [print(' ',p.split('/')[-1].replace('-','_')) for p in glob.glob(os.path.dirname(importlib.import_module('ta_lib_bin').__file__)+'/*') if os.path.isdir(p)]" 2>/dev/null || true
echo BIN_PROBE_SCRIPT_END
