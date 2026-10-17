# fpga

Random FPGA projects for the Sipeed Tang Nano 20K (Gowin GW2AR-18C, QN88).
Open-source flow via [APIO](https://github.com/FPGAwars/apio): yosys, nextpnr-himbaechel, gowin_pack, openFPGALoader.

## Why this repo exists

The board was bought after reading Hackaday's "The FPGA Chronicles" series by Al Williams. We bought it from Amazon (WayPonDEV listing, ASIN B0C5XJV83K). Saved copies of the articles, comments included, are in `docs/hackaday-fpga-chronicles/`.

| # | Article | Published | Topic | What we used | What we did not use |
|---|---|---|---|---|---|
| 1 | [Exploring The Tang Nano 20K](https://hackaday.com/2026/09/28/the-fpga-chronicles-exploring-the-tang-nano-20k/) | 2026-09-28 | The board and Gowin's vendor IDE | Starting point for choosing the board | Gowin IDE: not installed, not needed so far |
| 2 | [Open Source It](https://hackaday.com/2026/10/05/the-fpga-chronicles-open-source-it/) | 2026-10-05 | The open-source flow through APIO | APIO, the `apio.ini` format with `board = sipeed-tang-nano-20k`, openFPGALoader | The VS Code extension, the RAM/flash environments. The article's `libreadline` conflict did not show up here. |
| 3 | [Ready To Probe](https://hackaday.com/2026/10/13/the-fpga-chronicles-ready-to-probe/) | 2026-10-13 | Gowin's GAO logic analyzer | Nothing yet | GAO is part of the vendor IDE. The open-source flow has no equivalent installed. Article 2 mentions verifla as an alternative, untried. |

## Lessons learned

These come from setting the board up and running two designs, not from the articles.

- **The open-source flow is enough.** A 6-LED design builds in about 9 seconds with `apio build` and loads over JTAG. No vendor tools were needed.
- **The "FT2232" is the board's BL616.** It shows up as `0403:6010`, so use `openFPGALoader -c ft2232` and install the udev rule. Channel A is JTAG and channel B is the UART.
- **Back up the flash before changing anything.** The board was not blank. It held a LiteX SoC, and we dumped the full 8 MB first (`reference/`).
- **Load to SRAM first.** It is volatile and a power cycle restores whatever is in flash. Write flash only once a design is trusted.
- **JTAG can drop out.** Detection once returned an empty chain until the board was unplugged and replugged. A USB reset did not help. The `empty` line openFPGALoader prints is not a result. Look for the `idcode` line.
- **The UART belongs to whatever the FPGA is running.** With the LiteX design loaded, the serial port showed a LiteX prompt. The BL616 console that article 2 describes (`^X^C`) did not appear. When our design runs, the port is ours.
- **We did not need the programmable clock.** The 27 MHz crystal on pin 4 clocks the design directly, so the BL616's clock commands were never touched.
- **We have not simulated anything yet.** The one bug so far, an off-by-one in the UART message, was caught by rereading before loading. Testbenches are the next thing to add.
- **The toolchain is big.** `~/.apio` is about 3.2 GB. Put optional packages on another disk. See `developing.md`.

## Making something new

The high-level steps are in `developing.md`, under "Starting a new project".

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
