#!/usr/bin/env python3
# 第六轮 patch：放弃 release 资产直链（出口不可达），改用 codeload 源码 tarball 并在镜像内编译安装 TA-Lib
p = '/data/instock/build/Dockerfile'
lines = open(p, encoding='utf-8').read().splitlines()

lead = [
    '    mkdir ta-lib && \\',
    '    curl -SL https://codeload.github.com/ta-lib/ta-lib/tar.gz/refs/tags/v0.8.3 | tar -xz --strip-components=1 -C ./ta-lib && \\',
    '    (cd ta-lib && ./configure --prefix=/usr/local && make -j2 && make install) && ldconfig && \\',
]

out = []
done = False
for ln in lines:
    if 'ta-lib.deb' in ln:
        continue
    if 'pip install TA-Lib' in ln:
        out.extend(lead)
        out.append(ln)
        out.append('    rm -rf ta-lib* && \\')
        done = True
        continue
    out.append(ln)

assert done, '未找到 pip install TA-Lib 锚点行'
open(p, 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
print('PATCH6_OK')
