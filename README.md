# InStock 部署与本地补丁仓库

## 1. 仓库定位
本仓库只版本化官方上游 `myhhub/stock`（InStock 股票系统）基础上的部署改造、本地补丁、运维脚本与自建数据脚本；不入库上游源码全量、数据库文件、运行日志与备份产物。
- 远程仓库：`git@github.com:zxyduan/A_stock.git`（分支 `main`，建议设为 Private）
- 运行镜像：`mayanghua/instock:latest`（本机重建，含 TA-Lib 0.6.8）
- 容器：`InStock`（应用，宿主端口 9988，建议 SSH 隧道访问）、`InStockDbService`（MariaDB 10.6，库 `instockdb`）
- 编排：`docker-compose.yml`（持久化卷、healthcheck、restart always、只读补丁挂载）

## 2. 目录结构与正式产物
```
.
├── docker-compose.yml          # 编排权威文件
├── build/
│   ├── Dockerfile              # 本机重建镜像最终版（构建上下文 build/stock 不入库、磁盘保留）
│   └── cron/                   # 三个 run-parts 调度脚本（镜像构建上下文）
├── patches/                    # 运行时补丁层（ro 挂载；详见 patches/README.md）
├── ops/                        # 日常运维脚本
│   ├── ops.sh                  # 统一入口: bash ops/ops.sh status|health|counts|verify|kline-status ...
│   ├── backup_db.sh            # mariadb-dump gzip 备份，保留14天；宿主 crontab 每日03:17调用
│   ├── morning_check.sh        # 一键核查服务/数据覆盖/资源/备份
│   ├── quality_check.sh        # 历史日线主键去重/缺失/空值/分布质控
│   └── sync_loader.sh          # 权威入库脚本 -> 运行副本 md5 对账同步
├── jobs/
│   └── kline_history_loader.py # 自建前复权日线入库权威源（运行副本位于 app/cache，被 ignore）
├── init/
│   ├── init_schema.sql         # 补充幂等建表
│   └── hardening.sh            # 一次性加固: swap/首次备份/备份 cron/构建缓存清理
└── docs/                       # 部署方案、数据流、质控与收尾记录手册
```

不入库内容见 `.gitignore`：`mariadb/data`、`backup/*.sql.gz`、`app/cache`、`app/log`、`*.log`、凭据文件、`build/stock`、`src`、归档目录 `.archive-oneoff`。

## 3. 关键自定义说明
- `patches/eastmoney_fetcher.py`：只读挂载覆盖镜像同名文件，Accept-Encoding 降级 `gzip,deflate`，修复东财 br 编码导致的 `r.json()` 报错。
- `jobs/kline_history_loader.py`：自建表 `cn_stock_daily_kline`（主键 `code,date,adjust` + `INSERT IGNORE`）；直接调 `stock_zh_a_hist` 绕过上游历史链路；权威源在 `jobs/`，执行副本在 `app/cache/kline_history_loader.py`，改动后 `bash ops/sync_loader.sh` 同步；非常驻、无需重启容器。
- 备份 cron：`17 3 * * * /data/instock/ops/backup_db.sh >> /data/instock/backup/backup.log 2>&1`。

## 4. 恢复与重建步骤
1. 安装 Docker 与 docker compose 插件；准备 `mariadb:latest`；应用镜像可拉取 `mayanghua/instock:latest` 或按 `build/Dockerfile` 本机重建（构建上下文含 `build/stock` 上游只读副本，磁盘保留、不入 Git）。
2. 克隆本仓库到 `/data/instock`，按 `docker-compose.yml` 卷挂载点创建 `mariadb/data`、`app/cache`、`app/log`。
3. 手工创建 `eastmoney_cookie.txt`、`proxy.txt`（不入库）；按需 `bash ops/sync_loader.sh` 同步入库脚本。
4. 数据库恢复：历史 `sql.gz` 放入 `backup/`，参照 `ops/backup_db.sh` 的反向导入逻辑执行。
5. `docker compose up -d`，等待 DB healthy 后应用自动启动；补丁由 compose 只读挂载生效，改补丁后 `docker compose restart instock`。

## 5. 日常使用
```bash
bash /data/instock/ops/ops.sh health          # 综合体检
bash /data/instock/ops/ops.sh counts          # 核心表行数与最新日期
bash /data/instock/ops/ops.sh kline-status    # 自建历史日线进度/覆盖
cd /data/instock && git add -A && git commit -m "说明本次改动"
```

## 6. 边界与注意
- 本仓库不是上游源码 fork，不跟踪上游提交历史；上游升级优先换镜像 tag 并回归验证补丁兼容性。
- 待办路线：pandas CoW 就地写补丁（路线B）恢复指标/形态/策略/回测链；盘后增量入库 cron；Web 安全加固（本期建议仅 SSH 隧道访问 9988）；ETF/周月线/多复权口径扩展。详见 `docs/`。
- 数据源为公开爬虫接口，个人研究使用；无实盘下单能力（easytrader 绑定 Windows GUI）。
