# uart-baud

A copy of `projects/cmtz/cmtz-mul` (files copied, the original is untouched) with `sweep.py` on top. For each baud rate the script rewrites `CLKS_PER_BIT` in `cmtz_mul_uart.v` (27 MHz / baud), builds, loads to SRAM, checks all 289 products, and times 500 round trips.

```
source ../../env.sh
python3 -I sweep.py 115200 921600 3000000
```

Results on the Tang Nano 20K: all 289 pairs correct from 115200 up to 3000000 baud. The round trip stays at about 6 ms at every rate, so for one request and reply the limit is USB and host latency, not the baud rate. A bulk stream would gain from the faster rate.

`cmtz_mul_uart.v` is left at the last value tried, `CLKS_PER_BIT = 9` (3 Mbaud). 9 clocks per bit is the fastest this UART design can sample.
