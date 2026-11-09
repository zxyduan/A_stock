#!/usr/bin/env python3
# 第二轮 patch：基础镜像切到仍受支持的 bookworm；main/security apt 源统一走阿里云在线镜像
import re

p = '/data/instock/build/Dockerfile'
s = open(p, encoding='utf-8').read()

# 1) FROM 切换到 python:3.11-slim-bookworm（兼容 python:3.11-slim-* 任意 registry 前缀）
s2, n = re.subn(r'FROM\s+\S*python:3\.11-slim-\S+', 'FROM python:3.11-slim-bookworm', s, count=1)
assert n == 1, '未找到 python:3.11-slim 基础镜像 FROM 行'

# 2) security 源由官方改为阿里云 bookworm-security（官方 bullseye 旧修订已 404，bookworm 在线完整）
old_sec = 'RUN sed -i -e "s@http://deb.debian.org/debian-security@https://deb.debian.org/debian-security@g" \\'
new_sec = 'RUN sed -i -e "s@http://deb.debian.org/debian-security@https://mirrors.aliyun.com/debian-security@g" \\'
assert old_sec in s2, '未找到待改的 security sed 行'
s2 = s2.replace(old_sec, new_sec)

open(p, 'w', encoding='utf-8', newline='\n').write(s2)
print('PATCH2_OK')
