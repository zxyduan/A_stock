#!/usr/bin/env python3
# 将构建用 Dockerfile 的 apt 源策略改为：主源走阿里云镜像，security 走 Debian 官方源
# 原因：阿里云镜像只保留 bullseye-security 部分包，索引在但旧修订 .deb 为 404，导致编译依赖安装失败
p = '/data/instock/build/Dockerfile'
lines = open(p, encoding='utf-8').read().splitlines()
out = []
replaced = False
needle = 'mirrors.aliyun.com@g" /etc/apt/sources.list'
for ln in lines:
    if needle in ln:
        out.append('RUN sed -i -e "s@http://deb.debian.org/debian-security@https://deb.debian.org/debian-security@g" \\')
        out.append('    -e "s@http://deb.debian.org/debian@https://mirrors.aliyun.com/debian@g" /etc/apt/sources.list && \\')
        replaced = True
    else:
        out.append(ln)
assert replaced, '未找到待替换的源修改行，Dockerfile 可能已被改动'
open(p, 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
print('PATCHED_OK')
