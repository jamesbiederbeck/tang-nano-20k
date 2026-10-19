# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Monorepo of small FPGA projects for one board: the Sipeed Tang Nano 20K (Gowin GW2AR-18C, QN88). The repo is public on GitHub (`jamesbiederbeck/tang-nano-20k`). `README.md` has the overview and lessons learned; `developing.md` is the full record of what is installed on this machine, every system change made, pin facts, and the new-project steps.

## Commands

Everything FPGA-related lives in `.venv/` and `~/.apio/`. Nothing is on `PATH` until you run `source env.sh` (once per shell, from the repo root).

Run these from inside a project directory (`projects/<name>/`, or `projects/cmtz/<name>/`):

```
apio build                                     # yosys, nextpnr, gowin_pack -> _build/default/hardware.fs (about 10 s)
apio test                                      # all *_tb.v under iverilog
apio test stoplight_tb.v                       # one testbench
apio report                                    # utilization, fmax
openFPGALoader --detect                        # should print idcode 0x81b, GW2A(R)-18(C)
openFPGALoader -c ft2232 _build/default/hardware.fs       # load to SRAM (volatile)
openFPGALoader -c ft2232 -f _build/default/hardware.fs    # write SPI flash (persists)
```

`apio test` reports `[SUCCESS]` whenever iverilog and vvp run, even if the testbench printed `FAIL`. APIO expects `$fatal` on error; these testbenches print `PASS` or `FAIL` and call `$finish`. Read the `PASS`/`FAIL` line, not the final status. When you write a testbench, also break the design on purpose once and confirm it prints `FAIL`.

Diagrams: `python3 scripts/draw_diagrams.py` redraws the hand-made SVGs in `docs/diagrams/`. `scripts/generate-diagrams.sh projects/<name>` makes a Yosys/netlistsvg schematic (`<name>-rtl.svg`) and is only worth it for tiny modules.

## Board and toolchain facts that are not obvious

- The on-board BL616 debugger enumerates as an FT2232 (`0403:6010`). Interface 0 is JTAG, interface 1 is the FPGA's UART (`/dev/serial/by-id/usb-SIPEED_USB_Debugger_*-if01-port0`). `ftdi_sio` does not need to be unbound; the udev rule in `udev/` only grants access. Always pass `-c ft2232` to openFPGALoader.
- JTAG sometimes stops answering (`--detect` shows no `idcode` line). Unplug and replug the board; a USB reset does not help. The `empty` line openFPGALoader prints on every run means nothing.
- The BL616 buffers UART output. A test that reads the UART must first drain stale bytes (see `projects/cmtz/cmtz-mul/uart_test.py`), or old output from a previous design looks like replies.
- Pins confirmed on hardware: `clk` 4 (27 MHz crystal), LEDs 15 to 20 (active low), UART `tx` 69 / `rx` 70, HDMI 33 to 40, buttons S1 88 and S2 87 (`projects/game-of-life/pins.cst`). The pin table is in `developing.md`.
- In `pins.cst`, list each differential pin separately (`33` and `34` as two `IO_LOC` lines, not `33,34`) and use `IO_TYPE=LVDS25` without `BANK_VCCIO`; otherwise nextpnr or `gowin_pack` fails.
- Passing simulation does not prove the bitstream is right. Two cmtz projects (`cmtz-phasor-basics`, `cmtz-phasor-interference`) gave wrong answers on the chip with Yosys's default ALU mapping while `apio test` and post-synthesis simulation passed; `yosys-extra-options = -noalu` in `apio.ini` fixed them (commit `ea920de`; the cause is not isolated). Check designs with carry chains on the board, and try `-noalu` if hardware disagrees with simulation.
- The board shipped with a LiteX SoC in flash. The full 8 MB is backed up in `reference/tang-nano-20k-flash/`. Load to SRAM first and write flash only when a design is trusted and the user has said so.
- `/home` is nearly full. `~/.apio` is about 3.2 GB; the unused `openxc7` package lives on `/mnt/sdd1` behind a symlink.

## Project conventions

- A project is one folder with `apio.ini` (`board = sipeed-tang-nano-20k`, `top-module = ...`), Verilog, `pins.cst`, and `*_tb.v` testbenches. APIO compiles every `.v`/`.sv` in the folder.
- A top module that instantiates Gowin primitives (`rPLL`