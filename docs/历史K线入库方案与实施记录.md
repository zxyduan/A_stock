# A股历史日线入库方案与实施记录（自建表 `cn_stock_daily_kline`）

> 目标机：`root@139.196.74.136`，容器 `InStock` / `InStockDbService`，库 `instockdb`
> 实施日期：2026-11-08；数据来源：东方财富 `stock_zh_a_hist`（日线、前复权 qfq）
> 定位：**自建增强表，与上游 InStock 解耦**；不修改上游策略/指标逻辑，不替代上游信号表。

---

## 1. 为什么单独建这张表

上游 `myhhub/stock` 的设计：
- MySQL 存的是“某日截面结果”（实时快照、指标、形态、策略信号、回测收益）；
- **原始 OHLCV 日K不入库**，只在内存 DataFrame 与 `cache/hist/**/*.gzip.pickle` 缓存中；`CN_STOCK_HIST_DATA` 仅是列名模板，无建表语句；
- 快照类作业 `save_nph_*` 在历史日期模式下 `if before: return`，不会回填历史行情。

本方案用独立脚本把**个股前复权日线**批量落到 MySQL，供离线取数、自建回测与分析使用；上游 Web/策略仍按其原机制运行，互不影响。

## 2. 表结构（脚本自动 `CREATE TABLE IF NOT EXISTS`）

```sql
CREATE TABLE IF NOT EXISTS `cn_stock_daily_kline` (
  `code` varchar(10) NOT NULL COMMENT '证券代码',
  `name` varchar(32) DEFAULT NULL COMMENT '证券名称',
  `date` date NOT NULL COMMENT '交易日',
  `adjust` varchar(4) NOT NULL DEFAULT 'qfq' COMMENT '复权 qfq/hfq/none',
  `open` float, `close` float, `high` float, `low` float,
  `volume` double COMMENT '成交量(股)',
  `amount` double COMMENT '成交额(元)',
  `amplitude` float COMMENT '振幅',
  `p_change` float COMMENT '涨跌幅',
  `change_amount` float COMMENT '涨跌额',
  `turnover` float COMMENT '换手率',
  PRIMARY KEY (`code`,`date`,`adjust`),
  KEY `idx_date` (`date`),
  KEY `idx_name_code` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

- 主键 `(code,date,adjust)` 保证幂等：重跑用 `INSERT IGNORE`，已存在行不重复、不报错。
- `adjust` 预留复权口径；本期只写 `qfq`。

## 3. 数据来源与字段口径

| 上游中文列 | 入库列 | 说明 |
|---|---|---|
| 日期 | date | 交易日，截前10位 |
| 开盘/收盘/最高/最低 | open/close/high/low | 前复权价格 |
| 成交量 | volume | 东财原始手数口径，原样入库（不做×100换算，保持源口径，便于核对） |
| 成交额 | amount | 元 |
| 振幅 / 涨跌幅 / 涨跌额 / 换手率 | amplitude/p_change/change_amount/turnover | 百分比/金额 |

- 抓取函数：`instock.core.crawling.stock_hist_em.stock_zh_a_hist(symbol, period='daily', start_date, end_date, adjust='qfq')`；**直接调用底层抓取，绕过 `fetch_stock_hist`，因此不受 pandas 只读就地写 bug 影响**。
- 复权提示：`qfq` 前复权会随最新除权除息调整历史价；长期存档若需不可变序列，可另跑 `adjust='hfq'` 或 `''`（脚本已支持 `KLINE_ADJUST` 环境变量，同表靠 `adjust` 区分）。

## 4. 入库脚本 `kline_history_loader.py`

- 位置：宿主 `/data/instock/app/cache/kline_history_loader.py`；容器内 `/data/InStock/instock/cache/kline_history_loader.py`（缓存卷挂载，持久化、可直接编辑）。
- 股票池：优先 `SELECT code, MAX(name) FROM cn_stock_spot GROUP BY code`（当前约 4601 只）；空表时回退 `stock_zh_a_spot_em()` 实时全量。
- 并发与限速：`KLINE_WORKERS=6`（默认4），单只完成后随机 sleep 0.15–0.55s；单只失败重试 2 次后记入失败清单。
- 断点续跑：
  - `kline_done.txt` 成功代码清单（已完成自动跳过）；
  - `kline_failed.txt` 失败代码与错误；
  - `kline_progress.txt` 文本进度；`kline_history.log` 标准输出日志。
- 环境变量：

| 变量 | 默认 | 含义 |
|---|---|---|
| `KLINE_START` | `20210101` | 起始日 YYYYMMDD |
| `KLINE_END` | 今天 | 结束日 |
| `KLINE_ADJUST` | `qfq` | 复权口径 |
| `KLINE_WORKERS` | `4` | 并发线程（建议 ≤8，2vCPU） |
| `KLINE_LIMIT` | `0` | >0 时只跑前 N 只（验证用） |

## 5. 实施过程与实测（2026-11-08）

1. 小批量验证：`KLINE_LIMIT=20 KLINE_START=20240101`
   - 结果：`done=20 rows=13753 fail=0`；表内 `rows=13753, codes=20, min_date=2024-01-02, max_date=2026-11-06`，建表与主键生效。
2. 全量启动（统一口径、清空进度清单但保留表数据，靠 `INSERT IGNORE` 去重）：
   - 参数：`KLINE_START=20210101 KLINE_WORKERS=6 KLINE_ADJUST=qfq`；
   - `START total_pool=4601 todo=4601 workers=6 start=20210101 end=20261108`；
   - 宿主 `nohup docker exec ...` 后台运行，SSH 断开不影响；进程用 `docker top InStock | grep kline_history_loader` 查看（容器内无 `ps`）。
3. 共存影响：Web（`web_service.py`）与入库进程并存，实测 `curl /instock/=200`；cron 周末不触发，无冲突；2G swap 已加兜底。
4. **全量完成结果（2026-11-09 凌晨）**：`ALL_DONE`，`cn_stock_daily_kline` = **6,091,314 行 / 4,601 只 / 2021-01-04→2026-11-06 / adjust=qfq**；`kline_failed.txt=0`；`COUNT(*)=COUNT(DISTINCT code,date,adjust)` 无重复；`missing_codes=0`；`OHLC NULL=0`；次新股因上市晚行数少（4~37），属正常。

> 规模估算（以实测 `COUNT(*)` 为准，勿当精确值）：2021 起每只约 1300–1400 行 × 约 4600 只，粗估数百万行、InnoDB 含索引约 1–2GB；当前磁盘 `/` 可用约 28GB，空间充足。

## 6. 运行 / 重启 / 核查命令

```bash
# 查看进程(宿主侧, 容器内无ps)
docker top InStock | grep kline_history_loader

# 日志与进度
tail -f /data/instock/app/cache/kline_history.log
tail -f /data/instock/app/cache/kline_progress.txt
wc -l /data/instock/app/cache/kline_done.txt /data/instock/app/cache/kline_failed.txt

# 总量与覆盖
docker exec InStockDbService mariadb -uroot -proot instockdb -e \
 "SELECT COUNT(*) rows_cnt, COUNT(DISTINCT code) codes, MIN(date) mn, MAX(date) mx FROM cn_stock_daily_kline;"

# 抽样: 某票近期日线
docker exec InStockDbService mariadb -uroot -proot instockdb -e \
 "SELECT date,open,close,high,low,volume,p_change FROM cn_stock_daily_kline WHERE code='600519' ORDER BY date DESC LIMIT 5;"

# 失败清单(按清单补跑: 清掉对应done后重跑, 或单独执行)
cat /data/instock/app/cache/kline_failed.txt
```

### 6.1 启动 / 重启全量（宿主后台）

```bash
nohup docker exec InStock sh -c 'cd /data/InStock && PYTHONPATH=/data/InStock \
 KLINE_START=20210101 KLINE_WORKERS=6 python3 instock/cache/kline_history_loader.py \
 >> /data/InStock/instock/cache/kline_history.log 2>&1' \
 >/data/instock/app/cache/kline_host.out 2>&1 &
```

### 6.2 停止 / 重跑规则
- 停止：`docker top InStock | grep kline_history_loader` 取 PID 后 `kill <宿主PID>`；已 commit 的行保留，未提交事务回滚，不产生半截行。
- 断点续跑：直接再次启动即可，`kline_done.txt` 内代码自动跳过；
- 想强制重抓全区间：先 `: > /data/instock/app/cache/kline_done.txt`（表不清空，靠 `INSERT IGNORE` 去重补缺）。
- 每日增量（交易日盘后追加最新K线）：可复用同一脚本短窗启动，例如 `KLINE_START=20261101`；或后续加一条宿主 cron。

## 7. 边界与后续可选增强

1. 本期仅 **A股个股日线 qfq**；ETF 历史封装 `fund_etf_hist_em` 依赖实时映射，个别代码曾 `KeyError`，列入后续修复。
2. 周线/月线：底层接口支持 `period=weekly/monthly`，应用层未暴露；如需可扩展脚本参数。
3. 不复权 / 后复权：用 `KLINE_ADJUST` 另跑，写入同表不同 `adjust`。
4. 本表是“行情底座”，不写入上游 `cn_stock_indicators`/策略表；上游信号链路修复见附录 B。

## 附录 A. 阶段0加固结果（2026-11-08）

- Swap：新建 `/swapfile` 2G 并写入 `/etc/fstab`，`swapon` 生效；
- 备份：`/data/instock/backup_db.sh` 用 `mariadb-dump --single-transaction | gzip`，保留14天；首份 `instockdb_20261108_2359.sql.gz`（4.1M）；
- 调度：root crontab `17 3 * * *` 每日 03:17 备份；`cron` 服务 `active`；
- 空间：`docker builder prune -f` 清理未引用缓存；运行中镜像不删；`notalib-bak` 备份镜像(约1.5G)确认稳定后可手动 `docker rmi`。

## 附录 B. 待执行：上游 pandas 只读补丁（路线B，避免与入库争用，建议入库完成后再做）

背景：pandas 3.1.1 Copy-on-Write 恒开启，`.values[np.isnan()]=0.0` 就地写报错，共 102 处/8 文件（`calculate_indicator.py` 93、`stockfetch.py` 2、6 个策略文件 9）。直接 `compose` 重建会终止容器内 `docker exec` 的入库进程，故排在入库之后。

1. 先打通历史供给（`stockfetch.py` 两处 `p_change` 就地写改 `fillna`），只读挂载补丁；
2. 单票验证 `fetch_stock_hist` 非 None → 单票 `get_indicator` 出值 → 50 只小批 → 全市场；
3. 再替换 `calculate_indicator.py` 与策略文件同类写法；
4. 交易日盘后按 `indicators → klinepattern → strategy → backtest` 顺序跑信号链并核表；作业 `workers` 建议由 40 降到 8–16。
> 详细处理与命令见《InStock部署运维最终手册.md》§7/§9。
