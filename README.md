# fpga

Random FPGA projects for the Sipeed Tang Nano 20K (Gowin GW2AR-18C, QN88).
Open-source flow via [APIO](https://github.com/FPGAwars/apio): yosys, nextpnr-himbaechel, gowin_pack, openFPGALoader.

## Layout

| Path | What |
|---|---|
| `projects/<name>/` | One APIO project each: `apio.ini`, Verilog, `pins.cst` |
| `docs/` | Reading material saved for offline use |
| `reference/` | Dumps and notes from the board itself |
| `udev/` | udev rule that gives the `plugdev` group access to the on-board debugger |
| `developing.md` | What is installed, where, what was changed on this machine, workflow, pitfalls |
| `env.sh` | `source` it to put the APIO tools on `PATH` |

## Setup

```
python3 -m venv .venv && .venv/bin/pip install apio
.venv/bin/apio packages install      # about 3 GB into ~/.apio
sudo cp udev/99-fpga.rules /etc/udev/rules.d/ && sudo udevadm control --reload && sudo udevadm trigger
source env.sh
```

## Build and load

```
cd projects/hello
apio build
openFPGALoader -c ft2232 _build/default/hardware.fs        # to SRAM, gone on power cycle
openFPGALoader -c ft2232 -f _build/default/hardware.fs     # to flash, persists
```

## Board notes

- The on-board BL616 debugger enumerates as an FT2232 (`0403:6010`, "SIPEED USB Debugger"). Channel A is JTAG, channel B is the UART (`/dev/ttyUSB1` on this machine).
- Pins confirmed on this board: `clk` 4 (27 MHz crystal), LEDs 15 to 20 (active low), UART `tx` 69. `rx` is probably 70, not tested.
- JTAG sometimes stops answering until the board is power-cycled. A USB reset does not fix it.
- The board shipped with, or was left with, a LiteX SoC in flash. A dump is in `reference/tang-nano-20k-flash/`. To restore it:
  `openFPGALoader -c ft2232 -f reference/tang-nano-20k-flash/tang20k-flash-8M.bin`
  (not tested; the dump is 8 MB, the whole flash, and the bitstream is the first 907 KB).
