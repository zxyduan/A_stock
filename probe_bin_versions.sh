#!/bin/sh
export PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/
export PIP_DISABLE_PIP_VERSION_CHECK=1
echo "=== available ta-lib-bin versions ==="
pip install "ta-lib-bin==99.99" 2>&1 | grep -iE "from versions|Could not find"
echo "=== pip index versions ==="
pip index versions ta-lib-bin 2>&1 | head -20
echo "=== TA-Lib(官方绑定) available versions ==="
pip install "TA-Lib==99.99" 2>&1 | grep -iE "from versions|Could not find"
echo VERSION_PROBE_END
