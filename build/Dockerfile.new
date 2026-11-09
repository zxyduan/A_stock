# 基础镜像
# https://hub.docker.com/_/python/tags?page=1&name=3.11-slim-bookworm
FROM python:3.11-slim-bookworm

MAINTAINER myh
#增加语言utf-8
ENV LANG=zh_CN.UTF-8
ENV LC_CTYPE=zh_CN.UTF-8
ENV LC_ALL=C
ENV PYTHONPATH=/data/InStock
EXPOSE 9988

# 使用国内镜像地址加速：debian apt 与 pip 均走阿里云；设置时区 Asia/Shanghai
# 编译工具 gcc/make/python3-dev/build-essential 仅在本 RUN 内存在，尾部子 shell 清理；运行时保留 libta-lib0
RUN for f in /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources; do [ -f "$f" ] && sed -i -e "s@http://deb.debian.org/debian-security@https://mirrors.aliyun.com/debian-security@g" -e "s@http://deb.debian.org/debian@https://mirrors.aliyun.com/debian@g" "$f"; done && \
    printf '[global]\nindex-url = https://mirrors.aliyun.com/pypi/simple\ntrusted-host = mirrors.aliyun.com\n' > /etc/pip.conf && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    apt-get update && \
    apt-get install -y cron gcc make python3-dev default-libmysqlclient-dev build-essential pkg-config curl && \
    pip install supervisor && \
    pip install mysqlclient && \
    pip install requests && \
    pip install arrow && \
    pip install numpy && \
    pip install SQLAlchemy && \
    pip install PyMySQL && \
    pip install Logbook && \
    pip install python_dateutil && \
    pip install py_mini_racer && \
    pip install tqdm && \
    pip install beautifulsoup4 && \
    pip install bokeh && \
    pip install pandas && \
    pip install urllib3 && \
    pip install tornado && \
    pip install mini-racer && \
    pip install easytrader && \
    cd /tmp && \
    curl -fSL --retry 2 -o libta.deb https://mirrors.aliyun.com/debian/pool/main/t/ta-lib/libta-lib0_0.7.1-1_amd64.deb && \
    curl -fSL --retry 2 -o talib-dev.deb https://mirrors.aliyun.com/debian/pool/main/t/ta-lib/ta-lib-dev_0.7.1-1_amd64.deb && \
    (dpkg -i libta.deb talib-dev.deb || apt-get -f install -y) && \
    ldconfig && \
    pip install TA-Lib==0.6.8 && \
    python3 -c "import talib,numpy; assert len(talib.get_functions())>=100; print('BUILD_TALIB_OK', talib.__version__, talib.MA(numpy.array([1.,2.,3.,4.,5.,6.]),3))" && \
    rm -f /tmp/libta.deb /tmp/talib-dev.deb && \
    (apt-get --purge remove -y gcc make python3-dev default-libmysqlclient-dev build-essential curl || true) && \
    (rm -rf /root/.cache/* /var/lib/apt/lists/*; (apt-get clean || true); (apt-get autoclean || true); (apt-get autoremove -y || true))

WORKDIR /data
#InStock软件
COPY stock /data/InStock
COPY cron/cron.hourly /etc/cron.hourly
COPY cron/cron.workdayly /etc/cron.workdayly
COPY cron/cron.monthly /etc/cron.monthly

#add cron service. 任务调度
RUN chmod 755 /data/InStock/instock/bin/run_*.sh && \
    chmod 755 /etc/cron.hourly/* && chmod 755 /etc/cron.workdayly/* && chmod 755 /etc/cron.monthly/* && \
    printf 'SHELL=/bin/sh\nPATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\n*/30 9,10,11,13,14,15 * * 1-5 /bin/run-parts /etc/cron.hourly\n30 17 * * 1-5 /bin/run-parts /etc/cron.workdayly\n30 10 * * 3,6 /bin/run-parts /etc/cron.monthly\n' > /var/spool/cron/crontabs/root && \
    chmod 600 /var/spool/cron/crontabs/root

ENTRYPOINT ["supervisord","-n","-c","/data/InStock/supervisor/supervisord.conf"]
