#!/usr/bin/env python3
# 第五轮 patch：TA-Lib C 库由“源码 configure/make 编译”改为官方现成 amd64 deb 直装，
# 消除 2 核小机型上最耗时且易失败的 C 编译环节；pip TA-Lib 绑定保留在其后安装。
p = '/data/instock/build/Dockerfile'
lines = open(p, encoding='utf-8').read().splitlines()

new_block = [
    '    curl -SL -o /tmp/ta-lib.deb https://github.com/ta-lib/ta-lib/releases/download/v0.8.3/ta-lib_0.8.3_amd64.deb && \\',
    '    (dpkg -i /tmp/ta-lib.deb || apt-get -f install -y) && rm -f /tmp/ta-lib.deb && \\',
    '    pip install TA-Lib && \\',
]

out = []
i = 0
replaced = False
while i < len(lines):
    ln = lines[i]
    if 'mkdir ta-lib' in ln:
        # 跳过直到并包含 rm -rf ta-lib* 行
        j = i
        while j < len(lines) and 'rm -rf ta-lib*' not in lines[j]:
            j += 1
        if j >= len(lines):
            raise SystemExit('未找到 TA-Lib 段结束行 rm -rf ta-lib*')
        out.extend(new_block)
        replaced = True
        i = j + 1
        continue
    out.append(ln)
    i += 1

assert replaced, '未定位到 TA-Lib 源码编译段'
open(p, 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
print('PATCH5_OK')
