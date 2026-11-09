#!/usr/bin/env python3
# 第三轮 patch：bookworm 使用 deb822 格式 /etc/apt/sources.list.d/debian.sources，
# 让 sed 同时改写传统 list 与 deb822 文件，避免沿用慢速官方源
p = '/data/instock/build/Dockerfile'
s = open(p, encoding='utf-8').read()
old = '-e "s@http://deb.debian.org/debian@https://mirrors.aliyun.com/debian@g" /etc/apt/sources.list && \\'
new = '-e "s@http://deb.debian.org/debian@https://mirrors.aliyun.com/debian@g" /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources && \\'
assert old in s, '未找到待扩展的 sed 目标行'
open(p, 'w', encoding='utf-8', newline='\n').write(s.replace(old, new))
print('PATCH3_OK')
