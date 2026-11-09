import sys, requests
sys.path.insert(0, '/data/InStock')
import pandas as pd
import instock.core.indicator.calculate_indicator as idr

# 自包含: 直接拉 push2his 日K JSON -> DataFrame -> TA-Lib 全指标(对应 indicators job.prepare 的计算内核)
url = "http://push2his.eastmoney.com/api/qt/stock/kline/get"
params = {"fields1": "f1,f2,f3,f4,f5,f6",
          "fields2": "f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61,f116",
          "ut": "7eea3edcaed734bea9cbfc24409ed989", "klt": "101", "fqt": "1",
          "secid": "1.600519", "beg": "20230101", "end": "20500101"}
j = requests.get(url, params=params, timeout=12).json()
rows = [x.split(",") for x in j["data"]["klines"]]
df = pd.DataFrame(rows, columns=["date", "open", "close", "high", "low", "volume",
                                  "amount", "amp", "p_change", "chg", "turn"])
for c in ["open", "close", "high", "low", "volume", "amount", "p_change"]:
    df[c] = pd.to_numeric(df[c])
print("KLINE_ROWS=", len(df), "LAST_DATE=", df.iloc[-1]['date'])

out = idr.get_indicators(df.copy())
last = out.iloc[-1]
for k in ["macd", "macds", "kdjk", "kdjd", "kdjj", "rsi", "rsi_6", "rsi_12",
          "boll", "boll_ub", "boll_lb", "cr", "vr", "atr", "trix"]:
    if k in out.columns:
        print(f"IND_{k}={last[k]}")
core = ["macd", "kdjk", "rsi_6", "boll", "atr"]
nn = int(out[core].iloc[-1].notna().sum())
print("INDICATOR3_OK rows=", len(out), "core_nonnull=", nn, "/", len(core))
