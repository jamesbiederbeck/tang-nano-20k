# cmtz-core

A reusable Cook-Mertz processor for F_17 (q = 19). Unlike the other
`cmtz-*` projects, where every program is its own circuit, this bitstream runs
any program the Cook-Mertz compiler emits for this field, loaded over the UART
in milliseconds: compiled `.cmtz` programs, `matpow` with the matrix written
to data memory at run time, and hand-written assembly. Interrupt handlers
(`interrupt { }`) run on the live register file; the compiler proves on the
allocated machine code that they restore the registers they borrow.

The ISA, assembler, simulator and compiler backend are in `cmtz/isa/` and
`cmtz/backends/isa_backend.py` of the Cook-Mertz repo; the design notes are
in `docs/cmtz-processor.md` of this repo.

| | |
|---|---|
| Program memory | 512 x 32-bit instructions |
| Data memory | 1024 x 5 bits |
| Registers | R0..R31 field (5 bits, R0 = 0), X0..X15 index (16 bits, X0 = 0) |
| Return stack | 8 |
| Interrupts | one handler, no nesting, triggered over the UART |

## UART protocol

115200 8N1. One command byte, then arguments (big endian); the full
description is the docstring of `cmtz/isa/host.py`.

| Byte | Meaning |
|---|---|
| `I` | 21-byte info frame: `CMTC`, ISA version, p, q, memory sizes, core hash, loaded program length and crc32 |
| `P` | load a program: n, entry, handler (`FFFF` = none), n x 4 bytes; replies `00` + crc32 of the words |
| `W` | write a field register |
| `D` / `M` | write / read data memory |
| `S` | read R0..R31 and X0..X15 (64 bytes) |
| `G` | run; replies `00` at once |
| `Q` | 16-byte status: state, error, retired instructions, interrupt count, last dispatch |
| `T` | trigger the interrupt (works while running) |
| `X` | abort a run |

`0xFF` marks a refused command (every reply byte). A run resets the control
state only; registers and data memory keep their contents between runs.

LEDs (active low): 0 running, 1 halted, 2 error, 3 toggles per interrupt,
4 program loaded, 5 last reply was an error.

## Files

| File | What |
|---|---|
| `cmtz_core.v` | The processor. Generated. |
| `cmtz_core_uart.v` | Top module `cmtz_core_uart`: UART receiver, transmitter and the command state machine. Generated. |
| `cmtz_core_tb.v` | Core testbench: every real-field example, matpow, interrupts, an exhaustive sweep of every field instruction and every error code, run back to back on one core and checked against the simulator. Generated. |
| `cmtz_core_uart_tb.v` | Whole-design testbench over the UART pins, including an interrupt that lands mid-loop and the refusals. Generated. |
| `pins.cst` | `clk` pin 4, `tx` pin 69, `rx` pin 70, LEDs pins 15 to 20 |
| `apio.ini` | Board, top module, `-noalu` |

Regenerate with `examples/fpga/build_projects.py <dir> --core` in the
Cook-Mertz repo rather than editing the generated files.

## Build flag

`apio.ini` sets `yosys-extra-options = -noalu`, the default for every cmtz
project until it has been checked on the board both ways (see
`build_projects.py`).

## Test

```
source ../../../env.sh
apio test        # prints PASS for both testbenches
```

## Status

Both testbenches pass in simulation and `apio build` succeeds. Checked on the board with `examples/fpga/core_run.py` (2459 of 2459 checks, including the roots-of-unity projection programs; 4 of them confirm that register values outside F_p break restoration as predicted; see `docs/cmtz-projection.md` of this repo).
