import sys
sys.path.insert(0, '/data/InStock')
import instock.core.crawling.stock_hist_em as she
import instock.core.indicator.calculate_indicator as idr

# 绕开 fetch_stock_hist 的只读就地赋值, 直接取历史日K -> copy -> 标准列 -> TA-Lib指标
raw = she.stock_zh_a_hist(symbol="600519", period="daily", start_date="20230101", adjust="qfq")
print("RAW_ROWS=", 0 if raw is None else len(raw))
if raw is None or len(raw) == 0:
    print("HIST_EMPTY"); sys.exit(1)

d = raw.copy()
d = d.rename(columns={"日期": "date", "开盘": "open", "收盘": "close", "最高": "high",
                      "最低": "low", "成交量": "volume", "成交额": "amount", "涨跌幅": "p_change"})
out = idr.get_indicators(d)
last = out.iloc[-1]
for k in ["macd", "macds", "kdjk", "kdjd", "kdjj", "rsi", "rsi_6", "rsi_12",
          "boll", "boll_ub", "boll_lb", "cr", "vr", "atr", "trix"]:
    if k in out.columns:
        print(f"IND_{k}={last[k]}")
core = ["macd", "kdjk", "rsi_6", "boll", "atr"]
nn = int(out[core].iloc[-1].notna().sum())
print("INDICATOR2_OK rows=", len(out), "core_nonnull=", nn, "/", len(core))
