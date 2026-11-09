#!/usr/bin/env python3
# 第四轮 patch：
# 1) bookworm 无 /etc/apt/sources.list，sed 改为“文件存在才替换”的 for 循环，消除 can't read 报错
# 2) 尾部 apt purge/autoremove 加容错，避免个别包名差异导致整段 RUN 失败（只影响镜像体积，不影响运行）
p = '/data/instock/build/Dockerfile'
s = open(p, encoding='utf-8').read()

old_sed = (
    'RUN sed -i -e "s@http://deb.debian.org/debian-security@https://mirrors.aliyun.com/debian-security@g" \\\n'
    '    -e "s@http://deb.debian.org/debian@https://mirrors.aliyun.com/debian@g" /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources && \\'
)
new_sed = (
    'RUN for f in /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources; do [ -f "$f" ] && sed -i '
    '-e "s@http://deb.debian.org/debian-security@https://mirrors.aliyun.com/debian-security@g" '
    '-e "s@http://deb.debian.org/debian@https://mirrors.aliyun.com/debian@g" "$f"; done && \\'
)
assert old_sed in s, 'sed 源行未找到'
s = s.replace(old_sed, new_sed)

old_purge = '    apt-get --purge remove -y gcc make python3-dev default-libmysqlclient-dev curl && \\'
new_purge = '    apt-get --purge remove -y gcc make python3-dev default-libmysqlclient-dev curl || true && \\'
assert old_purge in s, 'purge 行未找到'
s = s.replace(old_purge, new_purge)

old_clean = '    rm -rf /root/.cache/* && rm -rf /var/lib/apt/lists/* && apt-get clean && apt-get autoclean && apt-get autoremove -y'
new_clean = '    rm -rf /root/.cache/* && rm -rf /var/lib/apt/lists/* && (apt-get clean || true) && (apt-get autoclean || true) && (apt-get autoremove -y || true)'
assert old_clean in s, 'clean 行未找到'
s = s.replace(old_clean, new_clean)

open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('PATCH4_OK')
