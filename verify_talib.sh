#!/bin/sh
# 一次性验证：在干净 bookworm 容器内用 autotools 从 codeload 源码构建 TA-Lib C 库并跑通 Python 绑定
set -e
export DEBIAN_FRONTEND=noninteractive
echo "== [0/6] switch apt mirror to aliyun =="
for f in /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources; do
  [ -f "$f" ] && sed -i -e "s@http://deb.debian.org/debian-security@https://mirrors.aliyun.com/debian-security@g" \
                        -e "s@http://deb.debian.org/debian@https://mirrors.aliyun.com/debian@g" "$f"
done
echo "== [1/6] install build deps =="
apt-get update
apt-get install -y autoconf automake libtool pkg-config gcc make
echo "== [2/6] download codeload source =="
cd /tmp
curl -SL --retry 2 -o tl.tgz https://codeload.github.com/ta-lib/ta-lib/tar.gz/refs/tags/v0.8.3
rm -rf tl && mkdir tl && tar xzf tl.tgz -C tl --strip-components=1
cd tl
echo "== [3/6] autogen (autoreconf -fi) =="
./autogen.sh
echo "== [4/6] configure =="
./configure --prefix=/usr/local
echo "== [5/6] make & install =="
make -j2
make install
ldconfig
echo "== [6/6] python binding =="
pip install TA-Lib
python3 -c "import talib; print('TALIB_IMPORT_OK', talib.__version__); print('MA=', talib.MA([1.0,2.0,3.0,4.0,5.0,6.0], timeperiod=3))"
echo VERIFY_DONE_OK
