# cmtz on the FPGA vs C++ on the CPU

Three cmtz programs (`cmtz-mul`, `cmtz-fibonacci`, `cmtz-ntt-butterfly`, all over F_17) against hand-written C++ doing the same arithmetic.

```
g++ -O3 -march=native -o bench bench.cpp && ./bench v        # CPU numbers, plus reference vectors
source ../../env.sh && python3 -I board.py cmtz-mul 1 2      # board: load, check 289 pairs, time UART
```

CPU: i5-6600K, g++ 12.2, `-O3 -march=native`, best of 7 (3 for latency). FPGA: Tang Nano 20K, 27 MHz crystal. `board.py` checked all 289 input pairs of each design against the C++ kernels: 0 mismatches.

| | mul | fibonacci (10 adds) | ntt-butterfly |
|---|---|---|---|
| CPU throughput (independent inputs) | 8770 Mop/s | 1000 Mop/s | 2790 Mop/s |
| CPU latency (dependent chain) | 2.8 ns | 11.3 ns | 8.3 ns |
| FPGA datapath throughput at 27 MHz | 27 Mop/s | 27 Mop/s | 27 Mop/s |
| FPGA datapath latency (clocks / ns) | 1 / 37 ns | 10 / 370 ns | 3 / 111 ns |
| FPGA UART ceiling (115200 8N1, wire time only) | 3.8 kop/s | 3.8 kop/s | 2.9 kop/s |
| FPGA measured end to end over UART | 167 op/s | 167 op/s | 167 op/s |

## Reading it

- **The CPU wins every row**, by 40x to 300x on throughput even against the datapath at its 27 MHz board clock. Nothing here is a close call.
- **The datapath is not the bottleneck on the board, the UART is.** The datapath accepts one result per clock, but the only way in is a 115200 baud serial link: 3 to 4 bytes per operation means at most 2.9 to 3.8 kop/s, about 7000x below the datapath's own rate.
- **The measured 167 op/s (6.00 ms per round trip) is host and USB latency, not the FPGA.** It is identical for all three designs, and the wire time is only 0.26 to 0.35 ms. The 6 ms is probably the debugger's buffering plus the 20 ms `select` poll granularity in `board.py`; I did not isolate which. Treat it as an upper bound on the overhead, not a property of the designs.
- The place-and-route fmax reported by `apio report` is 268 MHz (fibonacci) and 285 MHz (belief-propagation); I did not get a figure for mul or ntt. At those clocks the datapath would do about 270 Mop/s, still below the CPU, and the board's 27 MHz crystal would need a PLL to reach it.
- The CPU rows are for byte-sized F_17 values, where a modern core is very strong: `mul` auto-vectorizes, which is why it reaches 8.8 Gop/s. The latency rows use a dependent chain, so they show per-operation cost without pipelining or SIMD.

What the FPGA is good for here is not speed on these programs. These are toy F_17 circuits, and the point of the cmtz flow is that a program compiles to a fixed pipeline that runs at one result per clock with constant latency. That would only pay off with a fast I/O path (the datapath on-chip, fed by something other than a UART) and much wider data than 5 bits.
