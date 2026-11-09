# InStock（myhhub/stock）部署方案与服务器数据清单

> 目标机：阿里云 ECS `root@139.196.74.136`（stock-batch，华东2上海，Ubuntu 22.04，2vCPU/7.5GiB/40G，已装 Docker 29.9.3）
> 仓库：https://github.com/myhhub/stock.git （本地/服务器源码 commit b6e0ca2，2026-04-02）
> 生成口径：**资源、镜像、端口、网络、依赖、源码契约均为实测/源码逐行核对**；标注「待执行」的步骤尚未起容器验证，命令按源码与实测环境写好，执行后把结果回填到第 8 节验收表。

---

## 0. 一页结论

| 项 | 结论 |
|---|---|
| 服务器基础环境 | 达标：2 核 / 7.5GiB（可用约 6.0GiB）/ 磁盘剩 29G / Docker 正常；**无 swap**（见 6.5 可选加固） |
| 数据库镜像 | `mariadb:latest`（实为 10.6.5，560MB）**已拉取就绪** |
| 应用镜像 | `mayanghua/instock:latest`（1.52GB，ID `9aa157e57bb5`）已本地构建，Python 3.11.18、**43 个依赖已装齐** |
| 唯一阻塞 | **缺 TA-Lib**（C 库 `libta_lib.so.0` + Python 绑定 `talib`）。它是 Web 与全部数据作业的**顶层硬依赖**，不装上则 Web 启动即 `ModuleNotFoundError`、数据链路全断，无法绕开（影响面见 2.3） |
| 编排文件 | `/data/instock/docker-compose.yml` 纠偏版已写好并 `docker compose config --quiet` 通过；DB 卷已挂到官方真实路径 `/var/lib/mysql`、两容器 `restart: always`、DB 带 healthcheck、app 等 healthy 再起 |
| 行情网络 | 东财 `push2`/`push2his` 带参业务接口实测 **HTTP 200**、新浪 200，**直连无需代理**；Docker Hub 与 GitHub release 资产不可达（勿再重复尝试，见第 9 节死路清单） |
| 推荐落地顺序 | ① 用**免编译**方式补齐 TA-Lib（首选 Debian 官方 deb，备选 ta-lib-bin wheel）→ ② `docker compose up -d` 起 DB+Web → ③ 初始化并手动跑基础作业、核表 → ④ 按第 7 节手册运维 |
| 当前未完成 | 尚未起容器（0 容器）；Web 9988 未实测；业务表未建、无数据。原因即卡在 TA-Lib 安装方式上，本方案改用免编译捷径收敛 |

---

## 1. 服务器实测数据（"需要安装/具备什么"采集结果）

### 1.1 系统资源（实测 `free -h` / `df -h` / `uname -a`）

| 指标 | 实测值 | 部署含义 |
|---|---|---|
| 内核 / OS | Linux 5.15.0-198-generic，Ubuntu 22.04 64bit x86_64 | 与 Debian bookworm 容器体系兼容 |
| CPU | 2 vCPU（ecs.g8i.large） | TA-Lib 若编译用 `make -j2`；正常跑作业不打满 |
| 内存 | total 7.5Gi，used 1.2Gi，**available 6.0Gi**；**Swap 0B** | MariaDB + Tornado + 数据作业足够；无 swap，大批量抓取峰值建议加 swap 兜底（6.5） |
| 磁盘 | `/dev/nvme0n1p3` 40G，used 8.4G，**Avail 29G**（23%） | 余量充足；现有镜像 2.28G + 构建缓存 1.72G（可清，6.4） |
| 时间/时区 | 建议 `Asia/Shanghai`（compose 已注入 `TZ`；容器基础镜像已软链 Shanghai） | A 股交易日历按本地时间，需对齐 |

### 1.2 Docker 现状（`docker images` / `docker system df` / `docker ps -a`）

```
已拉取镜像：
  mariadb:latest              0f04ae6f30c5   560MB     就绪
  mayanghua/instock:latest    9aa157e57bb5   1.52GB    缺 TA-Lib，其余依赖齐全
  python:3.11-slim-bookworm   a83ba18aef0f   198MB     构建基础镜像（可留作重建）
  python:3.11-slim-bullseye   9e25f400253a   196MB     历史残留（Debian 11 EOL，可删）
容器：0 个运行 / 0 个停止；数据卷：0；Build Cache 18 条 1.722GB（可回收 1.71GB）
端口 9988、3306：当前空闲（ss 未占用）
```

### 1.3 服务器目录与持久化布局（`find /data/instock` 实测）

| 宿主机路径 | 用途 / 对应容器内路径 |
|---|---|
| `/data/instock/docker-compose.yml` | 纠偏版编排（待 #6 镜像补齐后 `up -d`） |
| `/data/instock/build/Dockerfile` | 本地构建文件（当前 TA-Lib 段失败待替换，见 4.1） |
| `/data/instock/build/stock/`、`build/cron/` | 构建上下文源码与 cron 片段 |
| `/data/instock/mariadb/data` → `/var/lib/mysql` | **数据库持久化**（当前空，首启由 MariaDB 初始化） |
| `/data/instock/app/log` → `/data/InStock/instock/log` | 应用日志（`stock_execute_job.log`、`stock_web.log`） |
| `/data/instock/app/cache` → `/data/InStock/instock/cache` | 行情历史 pickle 缓存 |
| `/data/instock/proxy.txt` → `.../config/proxy.txt` | 代理占位，**留空 = 直连**（本环境直连可用，勿填） |
| `/data/instock/eastmoney_cookie.txt` → `.../config/eastmoney_cookie.txt` | 东财 cookie 占位，留空用内置默认；触发限流再补 |
| `/data/instock/build_app.log` | 上次构建日志（依赖清单来源） |
| `/data/instock/src/stock-master`、`stock.tar.gz` | 源码留档 |

### 1.4 网络可达性实测（curl 带超时实测）

| 目标 | 结果 | 处置 |
|---|---|---|
| `https://push2.eastmoney.com/api/qt/clist/get?...`（实时行情带参） | **200** | 直连可用 |
| `https://push2his.eastmoney.com/api/qt/stock/kline/get?...`（历史 K 线带参） | **200** | 直连可用 |
| `https://finance.sina.com.cn`（新浪交易日历/数据） | **200** | 直连可用 |
| `https://mirrors.aliyun.com/pypi/simple/` | **200** | pip 走阿里云镜像 |
| `https://mirrors.aliyun.com/debian/pool/main/t/ta-lib/`（TA-Lib deb 目录） | **200** | **免编译 C 库来源** |
| `https://codeload.github.com`（源码 tarball） | 301（可达） | 仅源码可用，release 资产不可达 |
| `https://registry-1.docker.io`、`https://auth.docker.io` | **000 黑洞** | 公共镜像**拉不到**，勿再换加速器重试（已穷尽 8 个） |
| GitHub release 资产（`objects/release-assets` 签名直链） | 下载 `code=000 size=0` | 不用官方预编译 deb/资产直链 |
| ghfast.top / gh-proxy.com / mirror.ghproxy.com | **000** | 第三方 GitHub 代理均失效，勿用 |

---

## 2. 依赖盘点（"需要安装什么"的权威清单）

### 2.1 应用镜像内已成功安装的 Python 包（来源 `build_app.log` 的 `Successfully installed`，实测 43 个）

| 类别 | 包 @ 版本 |
|---|---|
| Web 框架 | tornado 6.6；flask 3.1.3、werkzeug 3.1.9、jinja2 3.1.6、itsdangerous 2.2.0、click 8.5.1、blinker 1.9.0、markupsafe 3.0.4 |
| 数据计算 | numpy 2.4.6、pandas 3.1.1、python-dateutil 4.0.0、tzdata 2026.6、typing-extensions 4.16.0、six 1.17.0、narwhals 2.28.0、contourpy 1.3.3、pillow 13.0.0、xyzservices 2026.9.1 |
| 数据库 | SQLAlchemy 2.1.8、PyMySQL 1.2.3、mysqlclient 2.3.0 |
| 可视化 | bokeh 3.9.2 |
| JS 引擎 | py_mini_racer 0.6.0、mini-racer 0.14.1 |
| 抓取/解析 | requests 2.34.2、urllib3 2.8.0、charset-normalizer 3.5.2、certifi 2026.10.23、idna 3.20、beautifulsoup4 4.15.0、lxml 6.1.3、pyquery 2.1.0、cssselect 1.6.0、soupsieve 4.0.1、tqdm 4.70.1、arrow 1.4.0、Logbook 1.10.1、PyYAML 6.0.3 |
| 交易模块（仅 Windows 用，Linux 不启动） | easytrader 0.23.7、easyutils 0.1.7、comtypes 1.4.17、pywinauto 0.6.6 |
| 进程守护 | supervisor 4.3.0 |

> 核对命令（镜像补齐后可复核）：
> ```bash
> docker run --rm --entrypoint sh mayanghua/instock:latest -c "python3 -V && pip list"
> ```

### 2.2 系统级 / C 库依赖（容器构建层）

| 依赖 | 现状 | 说明 |
|---|---|---|
| gcc / make / build-essential / pkg-config | 构建时装过、镜像尾部被 `purge` 清理 | 运行期无需；**重建时若编译 pip 绑定，须在 purge 之前完成 TA-Lib 安装** |
| default-libmysqlclient-dev | 构建时装、已 purge | mysqlclient 已在构建期编译完成，运行期不需要 dev |
| cron | 镜像内置，supervisord 拉起 `cron -f` | 无需额外安装 |
| **libta_lib.so.0（TA-Lib C 库）** | **缺失** | 必须安装（唯一系统级缺口） |
| 时区数据 | 已配置 Asia/Shanghai | 无 |

### 2.3 唯一缺口：TA-Lib 影响面（源码逐行确认，顶层硬导入，不可惰性降级）

| 文件（`instock/` 下） | 行号 | 导入方式 | 缺失后果 |
|---|---|---|---|
| `core/stockfetch.py` | 9 | `import talib as tl`（顶层） | 所有行情/历史/资金流抓取函数所在模块无法 import |
| `core/tablestructure.py` | 6 | `import talib as tl`（顶层） | 业务表结构定义模块无法 import（被 stockfetch、各作业引用） |
| `core/indicator/calculate_indicator.py` | 7 | `import talib as tl`（顶层） | 技术指标计算不可用 |
| `core/strategy/enter.py` / `keep_increasing.py` / `breakthrough_platform.py` / `climax_limitdown.py` / `backtrace_ma250.py` | 顶层 | `import talib` | 策略选股不可用 |
| `web/web_service.py` → `web/dataIndicatorsHandler.py` | 28 → 7 | 链：web_service 顶层 import handler → handler 顶层 `import stockfetch` → `import talib` | **Web 进程启动到 import 阶段即崩溃，9988 起不来** |

> 补充事实：`job/init_job.py` 只建库 + 建 `cn_stock_attention` 一张基础表，本身不 import talib；但 Web 与任何数据作业都依赖 talib。因此"先只起 Web、后补指标"不可行——必须先补 TA-Lib。

### 2.4 TA-Lib 版本匹配注意（避免装好报 undefined symbol）

- PyPI `TA-Lib`（Python 绑定，sdist 无 wheel，需链接 C 库头文件与 `libta_lib.so.0`）最新到 0.5.2；Debian bookworm pool 提供 C 库 `libta-lib0 0.7.1-1` 与开发头文件 `ta-lib-dev 0.7.1-1`。
- 链接后必须实测 `import talib` + 调用一个函数；若报 `undefined symbol`，说明 C 库 ABI 与绑定版本不匹配，按 4.1 的回退策略固定绑定版本或改用 4.2 的二进制 wheel。

---

## 3. 运行架构与容器契约（源码 + compose 核实）

### 3.1 拓扑

```
宿主机 9988 ──映射──> InStock 容器 :9988 (Tornado web_service.py, debug=True, 无登录)
                      ├─ supervisord 管理 3 个程序：
                      │   run_job  : 一次性跑 execute_daily_job.py（autorestart=false）
                      │   run_web  : 常驻 web_service.py（autorestart=true）
                      │   run_cron : cron -f（自动调度，autorestart=true）
                      └─ 网络 instock-net(bridge) ──> InStockDbService(MariaDB:3306)
DB 数据持久化到宿主机 /data/instock/mariadb/data:/var/lib/mysql
```

### 3.2 关键环境变量（`lib/database.py:21-36` 实测支持，compose 已注入）

| 环境变量 | compose 取值 | 作用 |
|---|---|---|
| `db_host` | `InStockDbService` | DB 主机（容器名走 bridge DNS） |
| `db_user` / `db_password` | root / root | 账号口令 |
| `db_database` | `instockdb` | 库名（`MYSQL_DATABASE=instockdb` 预建） |
| `db_port` | `3306` | 端口 |
| `TZ` | Asia/Shanghai | 时区 |

### 3.3 三进程启动脚本实测

- `bin/run_job.sh`：`python3 /data/InStock/instock/job/execute_daily_job.py`（前台一次性执行，脚本末尾仅 echo 作业说明）。
- `bin/run_web.sh`：`python3 /data/InStock/instock/web/web_service.py`，监听 9988。
- `bin/run_cron.sh`：`export PYTHONPATH=/data/InStock` 等，`printenv | grep -v no_proxy >> /etc/environment` 后 `/usr/sbin/cron -f`（让 cron 子任务继承容器环境变量）。
- 镜像 `ENTRYPOINT=["supervisord","-n","-c","/data/InStock/supervisor/supervisord.conf"]`，`PYTHONPATH=/data/InStock`。
- supervisord 内置 `inet_http_server port=*:9001`，但 **compose 未映射 9001 到宿主**，外部不可达（保持现状，勿暴露）。

### 3.4 自动调度（镜像内 `/var/spool/cron/crontabs/root` 实测）

| 时间（工作日=周一至周五） | 执行内容 |
|---|---|
| `*/30 9,10,11,13,14,15 * * 1-5` | `/etc/cron.hourly/basic_data_daily_job.py`（盘中基础实时数据，每 30 分钟） |
| `30 17 * * 1-5` | `/etc/cron.workdayly/execute_daily_job.py`（盘后整体作业） |
| `30 10 * * 3,6`（周三、周六） | `/etc/cron.monthly/` 清理 `cache/hist` 缓存 |

---

## 4. 推荐落地方案（按序执行；4.1 为首选）

### 4.1 首选：重建镜像补 TA-Lib（Debian 官方免编译 C 库 + pip 绑定）

思路：把当前 Dockerfile 中失败的"GitHub 源码编译"段，替换为"阿里云 Debian pool 现成 deb 提供 C 库与头文件 + 在仍有 gcc 的构建层 `pip install TA-Lib`"，不依赖 GitHub、不下载源码编译 C 库，速度最快、ABI 由 Debian 官方保证。

**(1) 替换 `/data/instock/build/Dockerfile` 的 TA-Lib 段**（当前失败段：`mkdir ta-lib && curl codeload … ./configure …`；改为下面等价块，位置在 `pip install easytrader` 之后、`pip install TA-Lib` 处）：

```dockerfile
    # TA-Lib C 库：Debian bookworm 官方 pool（阿里云镜像，免源码编译、免 GitHub）
    apt-get install -y --no-install-recommends \
        https://mirrors.aliyun.com/debian/pool/main/t/ta-lib/libta-lib0_0.7.1-1_amd64.deb \
        https://mirrors.aliyun.com/debian/pool/main/t/ta-lib/ta-lib-dev_0.7.1-1_amd64.deb && \
    pip install TA-Lib && \
    python3 -c "import talib, numpy; print('TALIB_OK', talib.__version__); print(talib.MA(numpy.array([1.,2.,3.,4.,5.,6.]),3))" && \
    ldconfig && \
```

> 要点：① 必须在 `apt-get purge gcc …` **之前**完成 `pip install TA-Lib`（绑定需 gcc 编译少量 C 扩展）；② 安装后立刻 `import talib` 自测，构建期就暴露 ABI 问题；③ 若 `import talib` 报 `undefined symbol: TA_…`，把 `pip install TA-Lib` 改为 `pip install TA-Lib==0.4.31`（更老绑定配 C 库兼容性通常更好）重试；④ 不再需要 `rm -rf ta-lib*`（没有源码目录）。

**(2) 重建（后台，日志落盘，避免 SSH 中断）**：

```bash
cd /data/instock/build
: > /data/instock/build_app.log
nohup sh -c 'docker build --network=host -t mayanghua/instock:latest . >> /data/instock/build_app.log 2>&1; echo BUILD_EXIT_CODE=$? >> /data/instock/build_app.log' >/dev/null 2>&1 &

# 观察：tail -f /data/instock/build_app.log ；成功标志 BUILD_EXIT_CODE=0 且日志含 TALIB_OK
```

**(3) 镜像内快速验收（只读）**：

```bash
docker run --rm --entrypoint sh mayanghua/instock:latest -c \
"python3 -c 'import talib,numpy; print(talib.MA(numpy.array([1.,2.,3.,4.,5.]),3))'"
# 期望输出一组浮点均值；再确认系统库：ldconfig -p | grep ta_lib
```

### 4.2 备选：应急免重建——ta-lib-bin 预编译 wheel（最快试跑，随后 commit 固化）

> 适用：想先快速验证 Web 能否起来、不等待重建。第三方 wheel 内含预编译 C 库，无需系统 deb 与 gcc。

```bash
# 1) 起一个临时容器（复用现有代码与环境），装二进制绑定
docker run -d --name talib_probe --entrypoint sh mayanghua/instock:latest -c "sleep 3600"
docker exec talib_probe pip install ta-lib-bin==0.4.26
# 2) 验证模块名与功能（若模块名不是 talib，退回 4.1）
docker exec talib_probe python3 -c "import talib; print('OK', talib.__version__); print(talib.MA([1,2,3,4,5],3))"
# 3) 验证通过则固化为新镜像，供 compose 使用（image 名按需改为 instock:talib）
docker commit talib_probe mayanghua/instock:latest
docker rm -f talib_probe
```

> 说明：`ta_lib_bin-0.4.26-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl` 已确认存在于阿里云 PyPI simple 索引；其对外模块名需在第 2 步确认（预期为 `talib`）。若不可用，仍以 4.1 为准。

### 4.3 起服务（4.1/4.2 任一让 `import talib` 通过后执行）

```bash
cd /data/instock
docker compose config --quiet            # 语法校验（此前已通过）
docker compose up -d
docker compose ps                          # 期望 InStockDbService healthy / InStock Up
```

### 4.4 初始化与数据链路实测（待执行，命令直接可用）

```bash
# (1) Web 存活（本机回环；公网访问方式见第 7.3 节安全建议）
curl -I http://127.0.0.1:9988/

# (2) 建库建基础表（init_job 只依赖 PyMySQL，独立可跑；业务表由下列作业按需创建）
docker exec InStock sh -lc 'cd /data/InStock && PYTHONPATH=/data/InStock python3 instock/job/init_job.py'

# (3) 基础实时数据作业（含 stockfetch→talib 调用链，用于验证 TA-Lib 全链路）
docker exec InStock sh -lc 'cd /data/InStock && PYTHONPATH=/data/InStock python3 instock/job/basic_data_daily_job.py'

# (4) 综合选股作业
docker exec InStock sh -lc 'cd /data/InStock && PYTHONPATH=/data/InStock python3 instock/job/selection_data_daily_job.py'

# (5) 指标 / 形态 / 策略（总作业不含，需手动单作业；验证 TA-Lib 计算）
docker exec InStock sh -lc 'cd /data/InStock && PYTHONPATH=/data/InStock python3 instock/job/indicators_data_daily_job.py'
docker exec InStock sh -lc 'cd /data/InStock && PYTHONPATH=/data/InStock python3 instock/job/klinepattern_data_daily_job.py'
docker exec InStock sh -lc 'cd /data/InStock && PYTHONPATH=/data/InStock python3 instock/job/strategy_data_daily_job.py'

# (6) 核表（替换为实际表名；先 list tables）
docker exec InStockDbService sh -c 'mysql -uroot -proot instockdb -e "show tables;"'
docker exec InStockDbService sh -c 'mysql -uroot -proot instockdb -e "select count(*) from <表名>;"'
```

> 手动单作业普遍支持日期参数（如 `indicators_data_daily_job.py 20261107`）；但 `execute_daily_job.py` 总作业**不解析命令行日期参数**（README 宣称的批量回填对总作业无效，见 5.1）。

---

## 5. 上游 README 漂移与自动调度边界（避免照抄踩坑，源码核实）

### 5.1 README 与源码不一致点

1. **总作业 `execute_daily_job.py` 的 main() 中，指标(gdj)、形态(kdj)、策略(sdj)、回测(bdj) 调用被注释**；自动/总作业只覆盖：建库 → 基础数据 → 综合选股 → 其他基础数据 → 盘后数据。指标/形态/策略/回测只能由对应单作业手动触发。
2. **总作业不解析命令行日期参数**（无 argv 处理）；README 中"整体作业带日期批量回填"对它无效；单作业经 `run_template.run_with_args` 才支持日期参数。
3. 上游 `docker-compose.yml` 把 MariaDB 数据卷误挂到 `/var/lib/instockdb`（官方真实目录 `/var/lib/mysql`），会导致数据不持久化；本方案已纠正。
4. 上游 compose 无 `restart`、无 DB healthcheck、未挂 cookie/日志；本方案补齐。
5. Web 无登录认证、`debug=True`、`xsrf_cookies=False`、`cookie_secret` 硬编码（安全见第 7 节）。
6. `easytrader` 交易模块绑定 Windows GUI（comtypes/pywinauto），Linux 容器不启动交易服务，仅做数据抓取/选股/展示，**不具备实盘下单能力**。

### 5.2 作业清单与是否自动触发

| 作业文件 | 作用 | 自动? |
|---|---|---|
| `init_job.py` | 建库 `instockdb` + 基础表 `cn_stock_attention` | 否（容器 run_job 流程首跑；DB 自建） |
| `basic_data_daily_job.py` | 盘中实时基础行情/资金流等 | **是**（工作日盘中每 30 分钟） |
| `execute_daily_job.py` | 盘后整体作业（仅基础/选股/盘后，注释了指标形态策略回测） | **是**（工作日 17:30） |
| `basic_data_other_daily_job.py` | 其他非实时基础数据 | 总作业内触发 |
| `basic_data_after_close_daily_job.py` | 盘后补充 | 总作业内触发 |
| `selection_data_daily_job.py` | 综合选股 | 总作业内触发 |
| `indicators_data_daily_job.py` | 技术指标（依赖 talib） | **否，需手动** |
| `klinepattern_data_daily_job.py` | K 线形态（依赖 talib） | **否，需手动** |
| `strategy_data_daily_job.py` | 策略信号（依赖 talib） | **否，需手动** |
| `backtest_data_daily_job.py` | 回测（依赖 talib） | **否，需手动** |

---

## 6. 运维手册（常用命令）

### 6.1 启停 / 状态

```bash
cd /data/instock
docker compose up -d          # 启动（含依赖顺序：DB healthy 后起 app）
docker compose ps             # 状态
docker compose restart        # 全部重启
docker compose restart instock   # 仅应用；数据库服务名 instockdb
docker compose down           # 停止并移除容器（数据卷/宿主目录保留，不丢库）
docker compose up -d --force-recreate instock   # 镜像更新后重建 app 容器
```

### 6.2 日志位置与查看

| 内容 | 路径 / 命令 |
|---|---|
| Web 日志 | 宿主机 `/data/instock/app/log/stock_web.log`；容器内 `/data/InStock/instock/log/stock_web.log` |
| 作业日志 | `/data/instock/app/log/stock_execute_job.log` |
| supervisord 主日志 | 容器内 `/tmp/supervisord.log`；`docker exec InStock supervisorctl status` |
| 实时跟随 | `docker logs -f InStock` / `docker logs -f InStockDbService` |

### 6.3 手动运行作业（统一模板）

```bash
docker exec InStock sh -lc 'cd /data/InStock && PYTHONPATH=/data/InStock \
  python3 instock/job/<作业文件名>.py [可选日期YYYYMMDD]'
```

### 6.4 磁盘清理（可选，回收约 1.7G 构建缓存；不影响已用镜像）

```bash
docker builder prune -f                 # 清构建缓存
docker image rm python:3.11-slim-bullseye   # 历史废弃基础镜像（Debian11 EOL）
docker system df                         # 复核
```

### 6.5 可选：加 swap（无 swap 时大批量作业内存峰值兜底）

```bash
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab && free -h
```

### 6.6 数据库备份 / 恢复

```bash
# 备份（MariaDB 10.6；容器内 mariadb-dump / mysqldump 均可）
mkdir -p /data/instock/backup
docker exec InStockDbService sh -c 'mariadb-dump -uroot -proot --single-transaction instockdb' \
  > /data/instock/backup/instockdb_$(date +%Y%m%d_%H%M).sql
# 恢复（先确保库存在）
docker exec -i InStockDbService sh -c 'mysql -uroot -proot instockdb' < /data/instock/backup/instockdb_YYYYMMDD_HHMM.sql
# 物理备份：停机后直接打包 /data/instock/mariadb/data
```

### 6.7 常见故障排查（静默失败优先看日志与表行数，不只看退出码）

| 现象 | 定位 / 处理 |
|---|---|
| Web 起不来、日志 `ModuleNotFoundError: No module named 'talib'` | TA-Lib 未装好；回到 4.1/4.2，确认 `ldconfig -p \| grep ta_lib` 与 `import talib` |
| 作业退出 0 但表为空/0 行 | 看 `stock_execute_job.log` 是否 `处理异常`；多为上游接口限流/缺 cookie/交易日非当天；核对表名与日期；不要只看进程退出码 |
| 连不上数据库 | `docker exec InStockDbService mariadb-admin ping -uroot -proot`；确认 compose 中 `db_host=InStockDbService` 与同一 `instock-net`；DB `healthy` 前 app 会重试 |
| 数据没落宿主目录 | 确认卷映射是 `/var/lib/mysql`（不是 `/var/lib/instockdb`）；`docker inspect InStockDbService` 查 Mounts |
| 抓不到行情 | 本环境直连，`proxy.txt` 保持空；若日志报代理错误，删除文件内容；触发限流再补 `eastmoney_cookie.txt` |
| 定时任务没跑 | `docker exec InStock ps \| grep cron`；`crontab -l`；确认工作日与交易时段；cron 子任务读 `/etc/environment`（run_cron.sh 已 printenv 注入） |
| 重建时 pip/apt 卡住 | 确认 `--network=host`；apt 用阿里云 Debian 源、pip 用阿里云 simple；不要走 Docker Hub / GitHub 资产 |

---

## 7. 安全与访问建议（重要）

1. **9988 无认证**：应用未做登录鉴权，且 `debug=True`。**不要直接把 0.0.0.0:9988 对全网开放**。两种推荐暴露方式二选一：
   - **方案 A（推荐，最安全）：SSH 本地隧道，不做安全组放行**
     ```bash
     # 在你本机执行，然后浏览器开 http://127.0.0.1:9988/
     ssh -L 9988:127.0.0.1:9988 aliyun
     ```
   - **方案 B：安全组白名单**：阿里云控制台 → 安全组 → 仅放行**你的办公/家庭出口 IP** 的 TCP 9988（不要 0.0.0.0/0）；该操作只能在控制台完成，命令行无法代做。
2. **supervisor 9001 管理端口**：镜像内监听 `*:9001`，compose 未映射到宿主；**切勿在 compose `ports` 暴露 9001**（无用户名口令，任何人可重启/查看进程）。
3. **数据库 3306 不映射宿主**：compose 当前只暴露 app 的 9988，DB 仅 bridge 内网互通，保持即可；如需外部连接再单独加白名单与强口令。
4. 生产化建议（可选后续）：前面加 Nginx/Caddy 反向代理并套 Basic Auth 或登录层；关闭 `debug=True`；修改默认 DB 口令与 `cookie_secret`；定期 `6.6` 备份。
5. `proxy.txt`、`eastmoney_cookie.txt` 留空即使用内置默认；文件已作为空占位挂载，勿提交真实 cookie 到版本库。

---

## 8. 执行验收清单（待跑通后回填结果）

| # | 验收项 | 命令 / 判据 | 状态 / 实测值 |
|---|---|---|---|
| 1 | TA-Lib C 库就位 | `ldconfig -p \| grep ta_lib` 有 `libta_lib.so.0` | 待执行 |
| 2 | Python 绑定可用 | `python3 -c "import talib; talib.MA([1,2,3],3)"` 无异常 | 待执行 |
| 3 | DB 健康 | `docker compose ps` 中 InStockDbService `healthy`；库 `instockdb` 存在 | 待执行 |
| 4 | Web 存活 | `curl -I http://127.0.0.1:9988/` 返回 200/302 | 待执行 |
| 5 | 建库建表 | `show tables;` 出现基础表；`cn_stock_attention` 可写 | 待执行 |
| 6 | 实时基础数据链路 | `basic_data_daily_job.py` 完成，主表 `count(*) > 0` | 待执行 |
| 7 | 综合选股 | `selection_data_daily_job.py` 完成并落表 | 待执行 |
| 8 | 指标链路（talib） | `indicators_data_daily_job.py` 完成、指标表非空 | 待执行 |
| 9 | 形态 / 策略 | `klinepattern` / `strategy` 单作业可跑通 | 待执行 |
| 10 | 持久化与自愈 | `docker compose restart` 后数据仍在、两容器自动 Up | 待执行 |
| 11 | 安全 | 9988 采用隧道或白名单；9001、3306 未对外暴露 | 待确认 |

---

## 9. 已验证不可达 / 已穷尽的死路（避免重复试错）

1. Docker Hub 直连 `registry-1.docker.io` / `auth.docker.io` = 000；8 个公开加速器（阿里云两个、baidu、dockerproxy、iscas、huecker、timeweb、noohub、daocloud）拉 `mayanghua/instock` 全部失败（not found / 超时 / 证书错 / 非白名单）。**结论：该镜像必须本地构建，不能在线拉取。**
2. Debian bullseye(11) security 源旧修订在镜像站 404（EOL），基础镜像已切到 `python:3.11-slim-bookworm`。
3. GitHub release 资产签名直链下载 `code=000 size=0`；三个第三方加速代理全 000；官方 release deb 与 release 源码包不可用。
4. codeload git tarball 不含预生成 `configure`（autotools 工程，需 `autoreconf -fi`/`./autogen.sh`），直接 `./configure` 报 `not found`；该路线慢且依赖编译，已降为末选。
5. 上次镜像构建因 `|| true` 容错吞掉了 TA-Lib 段失败，出现"构建退出 0 但缺 talib"的假象；本次重建必须在构建期显式 `import talib` 自测，不允许静默跳过。

---

## 附：一键执行顺序速查（4.1 路线，执行前确认 4.1(1) Dockerfile 替换完成）

```bash
# A. 重建并等待 TALIB_OK / BUILD_EXIT_CODE=0
cd /data/instock/build && : > /data/instock/build_app.log
nohup sh -c 'docker build --network=host -t mayanghua/instock:latest . >> /data/instock/build_app.log 2>&1; echo BUILD_EXIT_CODE=$? >> /data/instock/build_app.log' >/dev/null 2>&1 &
tail -f /data/instock/build_app.log

# B. 起服务
cd /data/instock && docker compose up -d && docker compose ps

# C. 初始化 + 基础/选股/指标作业（命令见 4.4），回填第 8 节验收表
```
