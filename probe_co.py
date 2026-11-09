import pandas as pd
import numpy as np
print("pandas", pd.__version__, "numpy", np.__version__)

s = pd.Series([1.0, np.nan, 3.0])
try:
    s.values[np.isnan(s.values)] = 0.0
    print("DEFAULT_WRITE_OK")
except Exception as e:
    print("DEFAULT_READONLY:", repr(e))

try:
    pd.options.mode.copy_on_write = False
    print("COW_OPTION_SET_OFF")
except Exception as e:
    print("COW_OPTION_UNSETTABLE:", repr(e))

s2 = pd.Series([1.0, np.nan, 3.0])
try:
    s2.values[np.isnan(s2.values)] = 0.0
    print("NOWCOW_WRITE_OK")
except Exception as e:
    print("NOWCOW_READONLY:", repr(e))
