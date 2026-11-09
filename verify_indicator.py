import sys
sys.path.insert(0, '/data/InStock')
import instock.core.stockfetch as stf
import instock.core.indicator.calculate_indicator as idr

# 1) 单只个股历史日K线(前复权, 含 p_change/volume 规范化), 走项目自有 fetch_stock_hist
df = stf.fetch_stock_hist(("2026-11-06", "600519"), "20230101", False)
print("HIST_ROWS=", None if df is None else len(df))
if df is None:
    print("HIST_FAIL"); sys.exit(1)
print("HIST_COLS=", list(df.columns))
print("HIST_LAST_DATE=", df.iloc[-1]['date'])

# 2) TA-Lib 全指标计算(对应 indicators_data_daily_job.prepare -> get_indicators)
out = idr.get_indicators(df)
last = out.iloc[-1]
checks = ["macd", "macds", "kdjk", "kdjd", "kdjj", "rsi", "rsi_6", "rsi_12",
          "boll", "boll_ub", "boll_lb", "cr", "vr", "atr", "trix"]
for k in checks:
    if k in out.columns:
        print(f"IND_{k}={last[k]}")
# 统计非空指标列数
nonnull = int(out[checks].iloc[-1].notna().sum())
print("INDICATOR_OK computed_rows=", len(out), "nonnull_checks=", nonnull)
