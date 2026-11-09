# 运行时补丁层（compose 只读挂载，不重建镜像）

原则：镜像内文件不直接改；本地差异由 `docker-compose.yml` 的 `volumes` 以 `:ro` 挂载覆盖。
回滚：删除对应挂载行后 `docker compose -f /data/instock/docker-compose.yml up -d instock`。

## 已生效补丁

| 仓内补丁文件 | 挂载到容器内路径 | 修复问题 |
|---|---|---|
| `eastmoney_fetcher.py` | `/data/InStock/instock/core/eastmoney_fetcher.py:ro` | 镜像未装 brotli，东财 br/zstd 编码返回导致长字段 `r.json()` 报错；请求头降级为 `gzip,deflate` |
| `core/stockfetch.py` | `/data/InStock/instock/core/stockfetch.py:ro` | pandas 3.1.1 CoW 下 `.values[np.isnan(...)]=0.0` 就地写只读报错，`fetch_stock_hist`/`fetch_etf_hist` 返回 None；改为 `fillna(0.0)`（2 处） |
| `core/indicator/calculate_indicator.py` | `/data/InStock/instock/core/indicator/calculate_indicator.py:ro` | 指标计算 74 处 NaN、14 处 Inf 就地写只读报错；NaN 改 `fillna(0.0)`，Inf 改 `replace([np.inf,-np.inf],0.0)`；注释行与读取型 `.values` 保留 |
| `core/strategy/backtrace_ma250.py` | `/data/InStock/instock/core/strategy/backtrace_ma250.py:ro` | `ma250` NaN 就地写 → `fillna(0.0)` |
| `core/strategy/climax_limitdown.py` | `/data/InStock/instock/core/strategy/climax_limitdown.py:ro` | `vol_ma5` NaN 就地写 → `fillna(0.0)` |
| `core/strategy/enter.py` | `/data/InStock/instock/core/strategy/enter.py:ro` | `vol_ma5` NaN 就地写 → `fillna(0.0)` |
| `core/strategy/keep_increasing.py` | `/data/InStock/instock/core/strategy/keep_increasing.py:ro` | `ma30` NaN 就地写 → `fillna(0.0)` |
| `core/strategy/breakthrough_platform.py` | `/data/InStock/instock/core/strategy/breakthrough_platform.py:ro` | `ma60` NaN 就地写 → `fillna(0.0)` |
| `job/execute_daily_job.py` | `/data/InStock/instock/job/execute_daily_job.py:ro` | 解除指标/形态/策略/回测 4 处 `main()` 注释，恢复调度总作业链路 |
| `job/indicators_data_daily_job.py` | `/data/InStock/instock/job/indicators_data_daily_job.py:ro` | `run_check` 线程数 `workers=40 → 8`（2 核主机降档，避免线程过载） |
| `job/klinepattern_data_daily_job.py` | `/data/InStock/instock/job/klinepattern_data_daily_job.py:ro` | `workers=40 → 8` |
| `job/strategy_data_daily_job.py` | `/data/InStock/instock/job/strategy_data_daily_job.py:ro` | `workers=40 → 8` |
| `job/backtest_data_daily_job.py` | `/data/InStock/instock/job/backtest_data_daily_job.py:ro` | `workers=40 → 8` |

## CoW 替换范式（pandas >= 3.0，CoW 恒开，`.values` 数组只读）

- NaN：`data['c'].values[np.isnan(data['c'].values)] = 0.0` → `data['c'] = data['c'].fillna(0.0)`
- Inf：`data['c'].values[np.isinf(data['c'].values)] = 0.0` → `data['c'] = data['c'].replace([np.inf, -np.inf], 0.0)`
- 安全写法：`data.loc[:, 'c'] = ...`、`data = data.copy()`、读取型 `.values`（如 `.values[0]`、`.values.astype(...)`）保持原样。
- 实测：显式 `.copy()` 后 `.values` 仍只读，故指标/策略站点必须整体替换，不能依赖副本豁免。

## 验证记录

- 单票 `fetch_stock_hist('600519')` 返回 `(727,12)`，`p_change` 无 NaN、`volume` 为 float64。
- 单票 `get_indicator` 返回 76 项、零 NaN/零零值；5 票小批函数层：指标 5/5、策略 50 次调用零异常、形态/回测按业务语义返回。
- `cn_stock_indicators` 表由作业 `prepare()` 自动建出并落 5 行实测指标值；其余信号表由对应作业首次运行自动建表。
- 全部补丁文件 `py_compile` 通过，调度模块 `IMPORT_OK`，Web `9988` 返回 200。

## 尚未落地（后续项）

- `web_service.py` 的 `debug=False`、`xsrf_cookies`、外置 `cookie_secret`、端口绑定 `127.0.0.1`（P1 安全项）。
- 盘后全量作业首次运行：建出 `cn_stock_pattern`、各 `cn_stock_strategy_*` 表并填充；`backtest_data_daily_job` 按信号表末列 NULL 回填未来收益率。
- `low_atr.py` 两处为注释代码、无有效站点，未挂载；其余无 CoW 站点的策略文件未挂载。
