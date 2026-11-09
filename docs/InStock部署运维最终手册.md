# InStock（myhhub/stock）部署运维最终手册

> 目标机：阿里云 ECS `root@139.196.74.136`（stock-batch，i-uf66dhxqhtpi23tu8ckuZ，华东2上海，Ubuntu 22.04.5，2vCPU/7.5GiB/ESSD 40G）
> 仓库：https://github.com/myhhub/stock.git （构建源码 commit b6e0ca2，2026-04-02）
> 部署实测日期：2026-11-08（周日，非交易日）。本手册所有状态、版本、行数、端口均为 2026-11-08 在服务器实测；早期《部署方案与服务器数据清单.md》中“待执行 / 备选 wheel / 0 容器 / 缺 TA-Lib”等结论已被本文取代。
> 客户端 SSH 别名：`aliyun`（`~/.ssh/config`，IdentityFile `C:\duanjia\aliyun\_aliyunmiyaodui.pem`）。

---

## 1. 部署状态总览（一页结论）

| 组件 | 状态 | 实测证据 / 判据 |
|---|---|---|
| MariaDB 数据库 | ✅ 运行、`healthy` | `InStockDbService` Up、`mariadb-admin ping` 通过；库 `instockdb`；数据目录 227M 落宿主 `/data/instock/mariadb/data` |
| 应用镜像（含 TA-Lib） | ✅ 在用 | `mayanghua/instock:latest` ID `16f0ce698022`，899MB；`talib 0.6.8`、158 个指标函数可用 |
| Web 服务（Tornado:9988） | ✅ 200 | `GET http://127.0.0.1:9988/instock/` → 200，页面标题 `<title>InStock股票系统</title>` |
| 抓取→落表链路 | ✅ 多条链路实测落库、无 Traceback | `cn_stock_spot` 4601、`cn_etf_spot` 1659、`cn_stock_selection` 4524、`cn_stock_fund_flow` 4512 等（见 §4） |
| 自动调度 | ✅ 进程就位、脚本存在 | `cron -f` 运行；`/etc/cron.hourly`、`/etc/cron.workdayly`、`/etc/cron.monthly` 三脚本就位（见 §5） |
| 自愈 / 开机拉起 | ✅ | 两容器 `restart=always`；app `depends_on: service_healthy` |
| 端口暴露面 | ✅ 最小化 | 宿主仅监听 `0.0.0.0:9988`；`3306`、supervisor `9001` 均未对外监听 |
| TA-Lib 指标 / 形态 / 策略全量落表 | ⚠️ 受限，见 §9.2 | 指标计算引擎可用；但全量作业在 pandas3 下触发上游只读赋值异常，周末未做全量落表，属已知兼容限制 |
| 实盘下单 | ❌ 不支持 | `easytrader` 仅 Windows GUI 绑定，Linux 容器只做数据抓取 / 指标 / 选股 / 展示 |

**一句话结论**：服务已可无人值守常驻（Web + DB + 定时基础数据调度），基础行情 / ETF / 选股 / 资金流等表已实测写入；技术指标及形态策略的“全量落表”需在交易日结合 §9.2 的后续路线处理，不影响当前服务运行与基础数据采集。

---

## 2. 环境与版本实测

### 2.1 服务器资源（实测 `free -h` / `df -h`）

| 项 | 实测 | 说明 |
|---|---|---|
| CPU | 2 vCPU（ecs.g8i.large） | 抓取 / 指标计算峰值不高 |
| 内存 | total 7.5Gi，used≈1.9Gi，available≈5.3Gi；**Swap 0B** | 建议大批量历史计算前按 §6.6 加 2G swap 兜底 |
| 磁盘 | `/dev/nvme0n1p3` 40G，已用约 9.9G（27%），余约 28G | 余量充足；可按 §6.5 清构建缓存与废弃镜像 |
| 时区 | 容器 `TZ=Asia/Shanghai`；宿主同步设置 | A 股交易日历按本地时间 |

### 2.2 镜像清单（`docker images`）

| 镜像 | ID | 大小 | 处置 |
|---|---|---|---|
| `mayanghua/instock:latest` | `16f0ce698022` | 899MB | **在用**（含 TA-Lib、gzip 补丁由只读卷提供） |
| `mariadb:latest`（MariaDB 10.6.5） | `0f04ae6f30c5` | 560MB | 在用 |
| `python:3.11-slim-bookworm` | `a83ba18aef0f` | 198MB | 构建基础镜像，可留作重建 |
| `python:3.11-slim-bullseye` | `9e25f400253a` | 196MB | Debian11 EOL 废弃，可删（§6.5） |
| `mayanghua/instock:notalib-bak` | `9aa157e57bb5` | 1.52GB | 早期缺 talib 备份，确认稳定后可删（§6.5） |

### 2.3 应用内运行时依赖（镜像内实测 `pip list`）

| 类别 | 版本 |
|---|---|
| TA-Lib（Python 绑定） | 0.6.8（对齐 `requirements.txt` 声明 `TA_Lib==0.6.8`，现场按当前 numpy 头文件编译） |
| numpy / pandas | numpy 2.4.6 / pandas 3.1.1（注意 pandas3 CoW 影响，见 §9.2） |
| Web | tornado 6.6 |
| 抓取 | requests 2.34.2、urllib3 2.8.0 |
| 数据库 | SQLAlchemy 2.1.8、PyMySQL 1.2.3、mysqlclient 2.3.0 |
| 可视化 / JS | bokeh 3.9.2、py_mini_racer 0.6.0 |
| 守护 | supervisor 4.3.0 |

> 复核命令：
> ```bash
> docker exec InStock python3 -c "import talib,numpy,pandas,tornado,requests; \
> print(talib.__version__, numpy.__version__, pandas.__version__, tornado.version, requests.__version__)"
> ```

---

## 3. 实际落地过程与三项关键修复（可复现）

### 3.1 TA-Lib：采用 “Debian 官方 deb C 库 + pip 绑定现场编译”

**最终做法（已成功构建 `16f0ce698022`）**：在仍含 gcc/make/python3-dev 的构建层，先下载安装 bookworm 官方预编译 C 库与头文件，再 `pip install TA-Lib==0.6.8`，并在同一 `RUN` 内立刻 `import talib` 自测（构建期即暴露 ABI 问题，不允许静默跳过）；purge 编译工具的容错关在子 shell 内，不再吞掉前面安装/自测的失败退出码。最终镜像内复测 `HEADER=gzip, deflate TALIB=0.6.8`、`libta-lib.so.0` 位于 `/lib/x86_64-linux-gnu/`。

最终 `Dockerfile` 关键片段（完整版在服务器 `/data/instock/build/Dockerfile`）：

```dockerfile
# TA-Lib C 库（Debian bookworm 官方 pool，经阿里云镜像，先下载再 dpkg -i）
RUN set -eux; \
    curl -fSL -o /tmp/libta.deb https://mirrors.aliyun.com/debian/pool/main/t/ta-lib/libta-lib0_0.7.1-1_amd64.deb; \
    curl -fSL -o /tmp/tadev.deb https://mirrors.aliyun.com/debian/pool/main/t/ta-lib/ta-lib-dev_0.7.1-1_amd64.deb; \
    dpkg -i /tmp/libta.deb /tmp/tadev.deb; \
    pip install --no-cache-dir TA-Lib==0.6.8 -i https://mirrors.aliyun.com/pypi/simple/; \
    python3 -c "import talib, numpy; print('BUILD_TALIB_OK', talib.__version__, len(talib.get_functions())); \
        print(talib.MA(numpy.array([1.,2.,3.,4.,5.,6.]),3))"; \
    ldconfig
# 注意: purge gcc/make/python3-dev/build-essential 必须放在上述安装与自测完成之后,
# 且不要用 `apt purge ... || true` 直接覆盖整条 RUN(会把前面真实失败也吞成退出0)。
```

**已否决 / 勿重试的路线（实测结论）**：
- `ta-lib-bin==0.4.26` wheel：仅 cp311 manylinux，按 numpy1.x ABI 编译，在 numpy2.4.6 下 `import talib` 报 `numpy.dtype size changed ... binary incompatibility`；且不应为迁就旧 wheel 去降级 numpy（会连锁破坏 pandas3 生态）。
- `apt-get install -y <deb直链URL>`：apt 把 URL 当包名，报 `Unable to locate package https://...`；正确做法是先 `curl -fSL` 下载再 `dpkg -i`（缺依赖接 `apt-get -f install -y`）。
- codeload 的 TA-Lib 源码 tarball 不含预生成 `configure`（autotools 工程需 `autoreconf`），直接 `./configure` 报 not found，慢且已弃用。
- 在线拉取公开 `mayanghua/instock`：Docker Hub `registry-1.docker.io/auth.docker.io` 为 000，8 个公开加速器均失败；镜像只能本地构建。

### 3.2 修复 “200 空响应 / r.json() Expecting value char 0”（br 解压不兼容）

**现象**：启动早期 `fetch_stocks` / `fetch_etfs` 日志报 `Expecting value: line 1 column 1 (char 0)`；三路对比（容器项目 fetcher、容器裸 requests、宿主 curl）到东财 clist/kline 接口本身均可达、HTTP 200。

**根因**（源码 + 抓包定位）：`instock/core/eastmoney_fetcher.py` 会话头硬写 `Accept-Encoding: gzip, deflate, br, zstd`，而镜像未装 brotli 解压库；完整长字段请求被东财以 `Content-Encoding: br` 返回，`requests` 无法解压，`r.text` 为压缩二进制乱码，`r.json()` 解析空体抛 JSONDecodeError。短字段请求常回 gzip 或不压缩，故“短参数 curl 成功、作业长参数崩溃”。

**修复（最小侵入、只读挂载、不改镜像层）**：将 `eastmoney_fetcher.py` 第 78 行请求头降级为 `'Accept-Encoding': 'gzip, deflate'`，其余代码不动，作为补丁文件只读挂载进容器：

```yaml
# /data/instock/docker-compose.yml -> services.instock.volumes 增加
- /data/instock/patches/eastmoney_fetcher.py:/data/InStock/instock/core/eastmoney_fetcher.py:ro
```

补丁源文件：宿主 `/data/instock/patches/eastmoney_fetcher.py`（由运行容器内同文件取出、仅替换该行生成；`grep Accept-Encoding` 应为 `'gzip, deflate'`，无 `br, zstd` 残留）。应用后实测：`ce=gzip status=200 len=30182 TOTAL=5927`，`r.json()` 正常。

> 重启/重建 app 容器后该只读卷仍然生效；若未来 `docker compose up --build` 重建镜像，镜像内旧头会被只读卷覆盖，行为保持一致。

### 3.3 docker-compose 纠偏（相对上游的四处纠正，已在生效文件中）

1. MariaDB 卷挂载到官方真实目录 `/var/lib/mysql`（上游误写 `/var/lib/instockdb`，会导致数据不落宿主持久化目录）。
2. 两容器 `restart: always`，异常退出 / 服务器重启后自愈。
3. DB 增加 `healthcheck`（`mariadb-admin ping`），app `depends_on: condition: service_healthy`，避免初始化抢跑。
4. 显式注入 `db_host/db_user/db_password/db_database/db_port`，不依赖镜像内默认值；并挂出日志、缓存目录与空代理 / cookie 占位文件。

生效文件：宿主 `/data/instock/docker-compose.yml`（`docker compose config --quiet` 通过）。

---

## 4. 数据库：表与本次实测行数（2026-11-08）

建表策略：`init_job.py` 仅建库与基础表 `cn_stock_attention`；其余业务表由对应作业按需 `checkTableIsExist` 后创建并按 `date,code` 去重写入。

| 表名 | 含义 | 精确行数 | 数据来源作业 |
|---|---|---|---|
| `cn_stock_spot` | 每日股票实时行情 | **4601** | `basic_data_daily_job.py` |
| `cn_etf_spot` | 每日 ETF 实时行情 | **1659** | `basic_data_daily_job.py` |
| `cn_stock_selection` | 综合选股 | **4524** | `selection_data_daily_job.py` |
| `cn_stock_fund_flow` | 个股资金流向 | 4512（近似） | `basic_data_other_daily_job.py` 等 |
| `cn_stock_spot_buy` | 基本面选股 | 126 | 对应基础作业 |
| `cn_stock_bonus` | 分红配送 | 932 | `basic_data_other_daily_job.py` |
| `cn_stock_lhb` | 龙虎榜 | 378 | 对应基础作业 |
| `cn_stock_blocktrade` | 大宗交易 | 16 | 对应基础作业 |
| `cn_stock_limitup_reason` | 涨停原因 | 33 | 对应基础作业 |
| `cn_stock_chip_race_open` / `_end` | 早盘 / 尾盘抢筹 | 各 100 | 对应基础作业 |
| `cn_stock_attention` | 我的关注（手工关注表） | 0 | `init_job.py` 建表 |
| `cn_stock_indicators` / `_buy` / `_sell` | 技术指标 / 买 / 卖信号 | 尚未落表（见 §9.2） | `indicators_data_daily_job.py` |

核表命令（MariaDB 10.6 容器内客户端为 `mariadb`，`mariadb-dump` 位于 `/usr/bin/mariadb-dump`）：

```bash
# 表清单（近似行数）
docker exec InStockDbService mariadb -uroot -proot -e \
 "SELECT table_name, table_rows FROM information_schema.tables \
  WHERE table_schema='instockdb' ORDER BY table_name;"
# 精确行数
docker exec InStockDbService mariadb -uroot -proot instockdb -e "SELECT COUNT(*) FROM cn_stock_spot;"
```

---

## 5. 自动调度机制（supervisord + 容器内 cron）

### 5.1 supervisord 三程序（`/data/InStock/supervisor/supervisord.conf`）

| 程序 | 命令 | autorestart | 作用 |
|---|---|---|---|
| `run_job` | `python3 .../execute_daily_job.py` | false（一次性） | 容器启动时跑一次盘后总作业 |
| `run_web` | `python3 .../web_service.py` | true | 常驻 Web，崩溃自愈 |
| `run_cron` | `/usr/sbin/cron -f` | true | 常驻定时调度 |

查看程序状态：
```bash
docker exec InStock supervisorctl status
```

### 5.2 容器 crontab + run-parts（实测 `/var/spool/cron/crontabs/root`）

```cron
*/30 9,10,11,13,14,15 * * 1-5 /bin/run-parts /etc/cron.hourly
30 17 * * 1-5           /bin/run-parts /etc/cron.workdayly
30 10 * * 3,6           /bin/run-parts /etc/cron.monthly
```

| 目录（run-parts 执行其中可执行脚本） | 脚本实测内容 | 触发时间（工作日=周一至周五） |
|---|---|---|
| `/etc/cron.hourly/run_hourly` | `python3 .../job/basic_data_daily_job.py` | 盘中 9/10/11/13/14/15 点每 30 分钟 |
| `/etc/cron.workdayly/run_workdayly` | `python3 .../job/execute_daily_job.py` | 工作日 17:30 盘后 |
| `/etc/cron.monthly/run_monthly` | `rm -rf /data/InStock/instock/cache/hist/*` | 周三、周六 10:30 清历史缓存 |

`run_cron.sh` 会先 `printenv | grep -v no_proxy >> /etc/environment`，保证 cron 子进程继承 `db_*`、`PYTHONPATH` 等容器环境变量。

### 5.3 调度边界（重要，勿被 README 误导）

1. **总作业 `execute_daily_job.py` 的 `main()` 中，指标、形态、策略、回测调用被注释**；自动 / 总作业只覆盖基础数据、综合选股、其他基础与盘后数据。
2. `indicators_data_daily_job.py`、`klinepattern_data_daily_job.py`、`strategy_data_daily_job.py`、`backtest_data_daily_job.py` **不会被自动调度**，需按 §6.3 手动触发（或后续自行加入 cron / run-parts）。
3. 总作业 `execute_daily_job.py` **不解析命令行日期参数**；仅各单作业经 `run_template.run_with_args` 支持 `python xxx.py 2026-11-06` 或逗号多日期 / 区间参数。

---

## 6. 日常运维命令（命令行可复现）

### 6.1 启停与状态

```bash
cd /data/instock
docker compose ps                          # 容器状态
docker compose up -d                        # 启动（DB healthy 后起 app）
docker compose restart                      # 全部重启
docker compose restart instock             # 仅重启应用；数据库服务名 instockdb
docker compose down                         # 停止并移除容器；数据卷 / 宿主目录保留、不丢库
docker compose up -d --force-recreate instock   # 应用镜像 / 补丁更新后重建 app
```

### 6.2 日志查看

| 内容 | 位置 / 命令 |
|---|---|
| Web 日志 | 宿主 `/data/instock/app/log/`；容器内 `/data/InStock/instock/log/` |
| 作业异常（`处理异常：...`） | 先 `docker logs --tail 200 InStock`；再看 `/data/instock/app/log/` 下日志 |
| supervisord 主日志 | 容器内 `/tmp/supervisord.log`；`docker exec InStock supervisorctl status` |
| 容器输出 | `docker logs -f InStock`、`docker logs -f InStockDbService` |

> 经验：**作业退出码为 0 ≠ 表有数据**；必须结合日志是否出现 `处理异常` 与 `SELECT COUNT(*)` 行数共同判断（静默失败最常见）。

### 6.3 手动运行作业模板

```bash
# 无参 = 取最近交易日；save_nph_* 函数 before=False 真正落表；其余函数用最近交易日单参
docker exec InStock sh -lc 'cd /data/InStock && PYTHONPATH=/data/InStock \
  python3 instock/job/<作业文件名>.py'

# 单作业支持指定日期(仅单作业; 总作业不支持)
docker exec InStock sh -lc 'cd /data/InStock && PYTHONPATH=/data/InStock \
  python3 instock/job/indicators_data_daily_job.py 2026-11-06'
```

常用单作业：`basic_data_daily_job.py`、`selection_data_daily_job.py`、`indicators_data_daily_job.py`、`klinepattern_data_daily_job.py`、`strategy_data_daily_job.py`、`backtest_data_daily_job.py`、`basic_data_other_daily_job.py`。

### 6.4 备份与恢复（`mariadb-dump` 实测存在于 DB 容器 `/usr/bin/mariadb-dump`）

```bash
mkdir -p /data/instock/backup
# 逻辑备份
docker exec InStockDbService sh -c 'mariadb-dump -uroot -proot --single-transaction instockdb' \
  > /data/instock/backup/instockdb_$(date +%Y%m%d_%H%M).sql
# 恢复(先确认 instockdb 库存在)
docker exec -i InStockDbService sh -c 'mariadb -uroot -proot instockdb' < /data/instock/backup/instockdb_YYYYMMDD_HHMM.sql
# 物理冷备: 停 app/db 后直接打包 /data/instock/mariadb/data
```

### 6.5 资源清理（可选，回收空间，不影响在线数据）

```bash
docker builder prune -f                         # 清构建缓存
docker image rm python:3.11-slim-bullseye      # 废弃基础镜像(Debian11 EOL)
# 确认稳定运行后可删缺 talib 的早期备份镜像:
# docker image rm mayanghua/instock:notalib-bak
docker system df                               # 复核镜像 / 缓存占用
```

### 6.6 可选：加 swap（当前 Swap 0B；大批量历史计算峰值兜底）

```bash
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab && free -h
```

---

## 7. 排错手册（区分“已解决”与“待后续”）

| 现象 / 报错 | 定性 | 判据与处理 |
|---|---|---|
| 作业日志 `Expecting value: line 1 column 1 (char 0)`（`fetch_stocks/fetch_etfs`） | ✅ 已修复 | 根因 br 解压不兼容（§3.2）。复发时：`docker exec InStock grep Accept-Encoding /data/InStock/instock/core/eastmoney_fetcher.py` 应为 `gzip, deflate`；确认补丁卷 `/data/instock/patches/eastmoney_fetcher.py` 存在并被 compose 只读挂载 |
| `ModuleNotFoundError: No module named 'talib'`，Web 起不来 | 构建缺陷 | 镜像未含 TA-Lib；按 §3.1 路线重建；确认 `ldconfig -p \| grep ta_lib` 与 `import talib` |
| indicators 作业无报错但 `cn_stock_indicators` 为空，日志 `assignment destination is read-only` | ⚠️ 已知兼容限制（§9.2） | 非网络、非缺库；是 pandas3 CoW 下上游 `.values[np.isnan()]=0` 就地写被拒。先确认非交易日因素，再按 §9.2 路线处理 |
| 作业退出 0 但表为 0 行 | 静默失败 | 看作业日志是否 `处理异常`；核对 `date` 过滤、是否非交易日、表名是否写错；不要只看退出码 |
| 应用连不上 DB | 连接 / 启动顺序 | `docker exec InStockDbService mariadb-admin ping -uroot -proot`；确认 `db_host=InStockDbService`、同一 `instock-net`；DB `healthy` 前 app 会重试 |
| 数据没落到宿主目录 | 卷路径错误 | 确认映射是 `/var/lib/mysql`（非 `/var/lib/instockdb`）；`docker inspect InStockDbService --format '{{json .Mounts}}'` |
| 抓不到行情 | 代理 / 限流 | 本环境直连可用，`proxy.txt` 保持空；若日志报代理错误，清空其内容；被限流再补 `eastmoney_cookie.txt` |
| 定时任务未触发 | 调度 / 时段 | `docker exec InStock supervisorctl status` 看 `run_cron`；`docker exec InStock crontab -l`；仅工作日交易时段触发；cron 子进程读 `/etc/environment`（已由 `run_cron.sh` 注入） |
| 重建镜像时 pip / apt 卡住 | 网络源 | 构建用 `--network=host`；apt 走阿里云 Debian 源、pip 走阿里云 simple；不走 Docker Hub / GitHub release 资产 |

---

## 8. 访问方式与安全建议

### 8.1 推荐：SSH 本地隧道（不对全网开放 9988）

在本机执行后，浏览器打开 `http://127.0.0.1:9988/instock/`：

```bash
ssh -L 9988:127.0.0.1:9988 aliyun
```

### 8.2 备选：安全组白名单（需在阿里云控制台操作，命令行无法代做）

仅放行**固定可信出口 IP** 的 TCP 9988；**不要**放行 `0.0.0.0/0`。

### 8.3 端口暴露现状（实测 `ss -tlnp`）

- 对外仅 `0.0.0.0:9988`（docker-proxy）；
- DB `3306`：未映射宿主，仅 bridge 内网 `InStockDbService:3306` 互通；
- supervisor `9001`：镜像内虽监听 `*:9001`，但 compose 未映射，宿主 `ss` 无 9001；**切勿在 `ports` 暴露 9001**（无用户名口令，可被用于查看 / 重启进程）。

### 8.4 应用自身风险与加固建议（现状默认值，未改动）

- Web **无登录认证**、`debug=True`、`xsrf_cookies=False`、`cookie_secret` 硬编码——必须通过 8.1 / 8.2 限制访问来源，避免裸奔公网。
- 生产化可选加固：前置 Nginx/Caddy + Basic Auth 或登录层；关闭 `debug`；修改 DB 默认口令与 `cookie_secret`；按 §6.4 定期备份。

---

## 9. 已知限制与后续路线（透明披露）

### 9.1 无实盘下单能力

`easytrader` 交易模块绑定 Windows GUI（comtypes / pywinauto），Linux 容器不启动交易服务；本部署仅提供**数据抓取、技术指标、形态 / 策略筛选、结果展示**，不具备下单 / 撤单能力。

### 9.2 指标全量落表的 pandas3 只读兼容问题（重点后续项）

- **现象复现**：`indicators_data_daily_job.prepare` → `run_check` → `calculate_indicator.get_indicators()` 在真实历史 K 线（实测 600519，930 根日 K）上，于 `data['macd'].values[np.isnan(data['macd'].values)] = 0.0` 处抛 `ValueError: assignment destination is read-only`；每股异常被 `run_check` 的 `try/except` 吞成日志，最终 `cn_stock_indicators` 为空。`stockfetch.fetch_stock_hist` 同型代码（volume / p_change 就地写）亦会触发。
- **根因**：镜像内为 pandas 3.1.1 + numpy 2.4.6；pandas≥3.0 Copy-on-Write **恒为开启、无法用 `mode.copy_on_write=False` 关闭**（实测设置该选项仅出 deprecation 警告且无效），上游大量 `.values[np.isnan(...)] = 0` 的就地写写法不再被允许。该问题与网络、缺 TA-Lib 无关——指标计算引擎（TA-Lib 函数）本身可用。
- **规模**：`calculate_indicator.py` 约 93 处此类就地赋值；另 `stockfetch.py` 约 2 处；策略文件少量。
- **后续路线 A（优先验证）**：在镜像内将 pandas 对齐到上游 `requirements.txt` 的 2.3.x（`numpy` 随之回归兼容版本），重建后跑 `indicators_data_daily_job.py` 验证；需注意 pandas2 对其它包的连锁兼容，属于镜像级变更，建议在测试通道先验证再上线。
- **后续路线 B**：不降级运行时，把就地写统一改为 pandas 向、可写等价写法，例如 `data['x'] = data['x'].fillna(0.0)`、`data['x'] = data['x'].replace([np.inf,-np.inf],0).fillna(0)`；改造点集中在 `calculate_indicator.py` 与 `stockfetch.fetch_stock_hist`，可通过补丁挂载或提交上游 PR 解决。
- **建议时机**：交易日盘中 / 盘后再评估全量指标作业；周末非交易时段不做强跑（历史 K 线全量 ×40 线程在 2vCPU/5Mbps 下耗时长，且当日无实时收盘数据）。

### 9.3 形态 / 策略作业未本次全量验证

`klinepattern_data_daily_job.py`、`strategy_data_daily_job.py` 依赖同一历史 K 线链与 TA-Lib；本次仅验证了抓取与引擎可用，未做全量落表。建议交易日按 §6.3 手动执行并核表；若同样触发 §9.2 只读异常，按 §9.2 路线处理。

### 9.4 非交易日数据判读

周日 / 节假日无实时撮合，实时表写入的是最近一个交易日快照；判断“作业是否成功”应以 **日志无 Traceback / `处理异常` + 表结构建成 + 关键表非空** 为准，而非苛求行数等于全市场总数。

### 9.5 上游设计性边界

- 自动总作业不含指标 / 形态 / 策略 / 回测（§5.3）。
- `easytrader` 不适用 Linux（§9.1）。
- 上游 compose / README 存在多处漂移（卷路径、总作业注释项、命令行日期参数不被总作业解析），已在 §3.3、§5 与本手册各节纠正。

---

## 10. 附录

### 10.1 关键路径速查

| 用途 | 宿主路径 | 容器内路径 |
|---|---|---|
| 编排文件 | `/data/instock/docker-compose.yml` | — |
| DB 持久化 | `/data/instock/mariadb/data` | `/var/lib/mysql` |
| 应用日志 | `/data/instock/app/log` | `/data/InStock/instock/log` |
| 历史缓存 | `/data/instock/app/cache` | `/data/InStock/instock/cache` |
| gzip 修复补丁 | `/data/instock/patches/eastmoney_fetcher.py` | `/data/InStock/instock/core/eastmoney_fetcher.py`（只读挂载） |
| 构建上下文 / Dockerfile | `/data/instock/build/` | — |
| 作业源码 | — | `/data/InStock/instock/job/` |
| 核心抓取 / 指标 | — | `/data/InStock/instock/core/`（`stockfetch.py`、`eastmoney_fetcher.py`、`indicator/calculate_indicator.py`） |
| 容器 / DB 名 | app=`InStock`，db=`InStockDbService`；服务名 `instock`、`instockdb` | — |

### 10.2 本次诊断 / 验证脚本（本地 `deploy/` 目录，服务器 `/data/instock/*.sh|*.py`）

- 服务状态与表行数：`collect_final.sh`、`poll_final.sh`
- 抓取 br 问题定位：`diag_fetch.sh`、`diag_fetch.py`、`patch_repro.py`、`verify_gzip.py`
- TA-Lib 构建期 / 运行时复测：`verify_final_image.sh`
- 指标计算链路：`verify_indicator.py` / `verify_indicator2.py` / `verify_indicator3.py`、`probe_co.py`
- 调度核查：`cron_probe.sh`；服务事实补采：`probe_final_facts.sh`

### 10.3 已穷尽、勿重复尝试的死路

1. Docker Hub 直连 `registry-1.docker.io` / `auth.docker.io` = 000；多个公开加速器拉 `mayanghua/instock` 全失败；**应用镜像只能本地构建**。
2. GitHub release 资产签名直链 `code=000 size=0`；`ghfast.top` / `gh-proxy.com` / `mirror.ghproxy.com` 等代理全 000。
3. `ta-lib-bin` wheel 与 numpy2 ABI 不兼容；`apt-get install <deb URL>` 无效；codeload TA-Lib 源码缺 `configure`；Debian bullseye(11) security 源已 404（EOL）。
4. 构建脚本尾部 `apt purge ... || true` 会吞掉 TA-Lib 安装失败、造成“退出 0 却缺 talib”的假象；关键依赖必须在构建期 `import` 自测。

### 10.4 验收清单最终判定（对应原 11 项）

| # | 验收项 | 判定 | 实测值 / 说明 |
|---|---|---|---|
| 1 | TA-Lib C 库就位 | ✅ | `libta-lib.so.0` 位于 `/lib/x86_64-linux-gnu/` |
| 2 | Python 绑定可用 | ✅ | `talib 0.6.8`，`MA` 等 158 个函数可调用 |
| 3 | DB 健康 / 库存在 | ✅ | `InStockDbService` healthy，库 `instockdb`，数据目录 227M |
| 4 | Web 存活 | ✅ | `GET /instock/` = 200，标题《InStock股票系统》 |
| 5 | 建库建表 | ✅ | `init_job.py` RC=0；`cn_stock_attention` 已建（0 行），业务表由作业创建 |
| 6 | 实时基础数据链路 | ✅ | `cn_stock_spot`=4601、`cn_etf_spot`=1659，无 Traceback |
| 7 | 综合选股落表 | ✅ | `cn_stock_selection`=4524 |
| 8 | 指标链路全量落表 | ⚠️ 受限 | 引擎可用；全量受 §9.2 pandas 只读兼容限制，待路线 A/B 处理 |
| 9 | 形态 / 策略作业 | ⚠️ 待交易日验证 | 引擎可用，全量未在周末强跑（§9.3） |
| 10 | 持久化与自愈 | ✅（机制就位） | `restart=always`×2、DB 卷持久化；`down`/`up` 不丢库；建议按 §6.4 周期备份 |
| 11 | 安全暴露面 | ✅ 达标 | 宿主仅监听 9988；3306 / 9001 未对外；访问走隧道或白名单（§8） |
