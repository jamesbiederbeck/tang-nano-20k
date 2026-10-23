# Developing

Everything FPGA-related on this machine was set up in one Claude Code session on 2026-10-17. Nothing was installed before that, so this file is the full inventory. If a tool is not listed here, it is not installed.

Target board: Sipeed Tang Nano 20K (Gowin GW2AR-18C, QN88, 8 MB SPI flash).

## What is installed

| What | Where | Size | Notes |
|---|---|---|---|
| APIO 1.6.0 | `.venv/` in this repo | 116 MB | Python 3.11.4 venv. Git-ignored. |
| APIO packages | `~/.apio/packages/` | about 3.2 GB | Installed with `apio packages install`. |
| `oss-cad-suite` | `~/.apio/packages/oss-cad-suite/` | 2.4 GB | The tools below. |
| `verible` | `~/.apio/packages/verible/` | 45 MB | Verilog formatter and linter. |
| `definitions` | `~/.apio/packages/definitions/` | 7 MB | APIO board and FPGA definitions. |
| `openxc7` | `/mnt/sdd1/victor-apio/openxc7` | 739 MB | Xilinx toolchain, not needed. Moved off `/home` to save space; `~/.apio/packages/openxc7` is a symlink to it. If `/mnt/sdd1` is not mounted, this package is broken and nothing else is affected. |

Tools in `oss-cad-suite/bin` that we have used or confirmed present:

| Tool | Version | Used for |
|---|---|---|
| `yosys` | 0.63+173 | Synthesis (`synth_gowin`) |
| `nextpnr-himbaechel` | | Place and route for `GW2AR-LV18QN88C8/I7`, `family=GW2A-18C` |
| `gowin_pack` | | Bitstream (`.fs`) generation |
| `openFPGALoader` | v1.1.1 | JTAG programming and flash dump |
| `iverilog`, `vvp`, `verilator`, `gtkwave`, `sby` | | Present in the package. Not used yet. |

Nothing is on your system `PATH` by default. `source env.sh` adds `.venv/bin` and the oss-cad-suite `bin` directory to `PATH` for that shell.

## System changes made with sudo

1. `/etc/udev/rules.d/99-fpga.rules`, copied from `udev/99-fpga.rules`. It gives the `plugdev` group (you are in it) access to the FT2232 at `0403:6010` and to Sipeed's `352f` vendor ID. udev was reloaded and triggered.
2. The `ftdi_sio` kernel driver was unbound from the debugger's JTAG interface (`1-5:1.0`) through sysfs. This is not persistent. A replug or reboot binds it again, and the serial port for that channel comes back.

Nothing else outside this repo and `~/.apio` was changed. No apt packages were installed.

## Board connection

The on-board BL616 debugger shows up as an FT2232 (`0403:6010`, product "USB Debugger", manufacturer SIPEED).

- Channel A (interface 0) is JTAG. openFPGALoader takes this one over through libusb.
- Channel B (interface 1) is the UART wired to the FPGA. On this machine it is `/dev/ttyUSB1` (`/dev/serial/by-id/usb-SIPEED_USB_Debugger_*-if01-port0`). The number depends on what else is plugged in, so use the `by-id` path in scripts.

## Starting a new project

High-level steps. Each one points at what we have actually done, and says so where we have not.

1. **Figure out the circuit.** Write down what goes in, what comes out, which clock it needs and what it does with it. Decide which board pins it uses (the on-board LEDs, buttons, UART, header pins) and check the pin map on the Sipeed wiki before choosing. Note anything active low: the on-board LEDs are.
2. **Make the project folder.**
   ```
   mkdir projects/<name> && cd projects/<name>
   cp ../hello/apio.ini . && $EDITOR apio.ini     # change top-module
   ```
3. **Write the Verilog.** One top module whose port names match the constraints file. Keep the clock a plain `input wire clk`.
4. **Write the pin constraints** in `pins.cst`, one `IO_LOC` and one `IO_PORT` line per port. Copy `projects/hello/pins.cst` and edit it. Use `IO_TYPE=LVCMOS33` for the 3.3 V pins.
5. **Simulate it.** Write a testbench named `<something>_tb.v` that prints `PASS` or `FAIL` and calls `$finish`, then run `apio test`. `projects/stoplight/` is the worked example. Make sure the testbench can fail: break the design on purpose once and confirm it complains. This is the cheapest place to catch a bug.
6. **Build.** `source env.sh && apio build`. Errors from yosys or nextpnr point at the Verilog or at a pin that does not exist.
7. **Load into SRAM.** `openFPGALoader -c ft2232 _build/default/hardware.fs`. It runs until the next power cycle, which brings back whatever is in flash.
8. **Check it on the board.** Watch the LEDs, or read the serial port as shown below. If JTAG stops answering, unplug and replug the board.
9. **Iterate** on steps 3 to 8. Loading to SRAM is cheap and safe.
10. **Flash it once you trust it.** `openFPGALoader -c ft2232 -f _build/default/hardware.fs` makes it boot at power-up. Check that `reference/tang-nano-20k-flash/` still holds the original backup first. We have not written to flash yet, so treat this step as untested.
11. **Commit it.** The `.gitignore` already skips `_build/` and `*.fs`. Update the pin table below if you confirm a new pin.

## Daily workflow

```
source env.sh
cd projects/<name>
apio build                                                 # yosys, nextpnr, gowin_pack
openFPGALoader -c ft2232 _build/default/hardware.fs        # load into SRAM, lost on power cycle
openFPGALoader -c ft2232 -f _build/default/hardware.fs     # write to flash, persists
openFPGALoader --detect                                    # should print idcode 0x81b, GW2A(R)-18(C)
```

A project needs an `apio.ini` and a `pins.cst`:

```
[env:default]
board = sipeed-tang-nano-20k
top-module = <module name>
```

`apio build` runs:

```
yosys -p "synth_gowin -top <top> -family gw2a -json hardware.json" -q -DSYNTHESIZE <files>
nextpnr-himbaechel --device GW2AR-LV18QN88C8/I7 --json hardware.json --write hardware.pnr.json --report hardware.pnr --vopt family=GW2A-18C --vopt cst=pins.cst -q
gowin_pack -d GW2A-18C -o hardware.fs hardware.pnr.json
```

Reading the serial port without installing anything:

```
python3 -I -c "
import os, glob, termios, time, select
fd = os.open(glob.glob('/dev/serial/by-id/usb-SIPEED_USB_Debugger_*-if01-port0')[0], os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK)
a = termios.tcgetattr(fd); a[0]=a[1]=a[3]=0; a[2]=termios.CS8|termios.CREAD|termios.CLOCAL; a[4]=a[5]=termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, a)
end=time.time()+4; out=b''
while time.time()<end:
    if select.select([fd],[],[],0.1)[0]: out+=os.read(fd,4096)
print(out.decode(errors='replace'))"
```

## Pins confirmed on this board

| Signal | Pin | How it was confirmed |
|---|---|---|
| `clk` | 4 | 27 MHz crystal. Clock-driven LED count ran. |
| LEDs 0 to 5 | 15 to 20 | Active low. Count pattern ran. |
| UART `tx` | 69 | Greeting read on the serial port. |
| UART `rx` | 70 | `projects/cmtz/cmtz-mul` answered all 294 test pairs, with `PULL_MODE=UP`. |
| HDMI TMDS | 33 to 40 | `projects/hdmi-test` shows a stable 720p picture. Clock on 33/34, data on 35/36, 37/38, 39/40. Use `IO_TYPE=LVDS25` without `BANK_VCCIO`. |
| Buttons S1, S2 | 88, 87 | `projects/game-of-life`: S1 shows the next seed, S2 the previous. `LVCMOS33`, `PULL_MODE=DOWN`; the design finds the active level itself. |

Pin map for the rest of the board is on the Sipeed wiki. A pin diagram image from the Amazon listing was used for the LED pins.

## Things that went wrong

- **`openFPGALoader -b tangnano20k` found no device** during the first attempt. At that time the JTAG chain was not answering at all, so the board preset was not the cause. `-c ft2232` works.
- **JTAG stopped answering for a while.** `--detect` found the GW2A-18 once, then printed an empty chain for several attempts. A USB reset (`USBDEVFS_RESET`) and the `ftdi_sio` unbind did not fix it. Unplugging the board and plugging it back in did. The cause is unknown.
- **Do not trust the line `empty` in openFPGALoader output.** It prints on every run, including successful ones. Look for the `idcode` line.
- **`openFPGALoader` needs the udev rule.** Without it, it fails with "Access denied (insufficient permissions)".
- **Hand-written Verilog off-by-one.** The first `hello.v` declared its message 28 bytes wide for a 27-byte string, which would have sent a stray `0x00` first. Fixed before the first load.

## Toolchain quirks

Measured on this machine with Yosys 0.63+173 and the `nextpnr-himbaechel` in
`~/.apio/packages/oss-cad-suite`, while working out why the 4-lane ML-KEM NTT in
`benchmarks/mlkem-ntt/` gave wrong answers on the board at 162 MHz and above. Re-check them
after a package update; they are toolchain behaviour, not board behaviour.

Two separate causes were at work in that design, and neither one showed up in the timing
report: high fan-out control nets, and untimed block-RAM paths. Fixing the fan-out is what
got the 4-lane core correct at 162 MHz.

- **A high fan-out net is not flagged, and nothing replicates its driver for you.** In the
  4-lane NTT one flip-flop, `core.wv`, drove 251 loads and `wv1` drove 136, and the
  place-and-route report named no path through either. Hand-replicating the driver, as
  per-bank `(* keep *)` copies, and dropping some redundant gating took the real 4-lane
  design from wrong at 162 MHz to 0 mismatches in 250 cycles on the board. A variant with
  the banks in LUT RAM and the ROM in LUTs, so no block RAM at all, was *worse* at
  162 MHz (50 of 256 coefficients wrong) and had a ROM address net with fan-out over 1000,
  which is what pointed at fan-out rather than at the memories. Count loads per net in the
  `_build` JSON when a design misbehaves above about 150 MHz; the report will not tell you.
- **`nextpnr-himbaechel` does not time BSRAM paths, so its fmax is meaningless for any
  design whose real critical path touches a block RAM.** A probe of an LFSR plus one
  1024x18 BSRAM read into a fabric flip-flop, and nothing else, reports
  `Max frequency 1098.90 MHz (PASS at 400.00 MHz)`. Its worst path *ends* at the BSRAM
  address pin (`Sink mem.0.0.ADA7`, `setup 0.03`, 0.91 ns total) and no path *starting* at
  the BSRAM output appears at all. An equivalent flip-flop to LUT to flip-flop design with
  no BSRAM reports 1154.73 MHz, so the BSRAM design is reported no slower than plain logic.
  In the NTT builds this shows up as a reported critical path that is always in the UART
  shim (`rst_cnt` to `lock` to `core.done` to `sendbuf` CE, 4.67 ns at 4 lanes) and never in
  the banks, the control ROM or the multipliers. It misses in both directions: a build
  reported as `192.05 MHz FAIL at 199.80` ran clean on the board, and one reported as
  `213.95 MHz PASS at 162.00` was wrong in 37 of 48 comparisons.
  Consequences worth remembering: a `PASS` does not mean the design closes; adding fabric
  pipeline stages after a BSRAM does not help, because the unmodelled part is the BSRAM's
  own access time plus the route to that register, and place-and-route sees that route as
  free, so it will not shorten it; and the real ceiling drops as you add block RAMs.
  Check such a design on the board at the clock you intend to use. In the NTT this was the
  smaller of the two causes at 162 MHz but is the suspected remaining gap above 180 MHz,
  where the 4-lane core still fails.
- **Yosys always puts inferred BSRAM in bypass read mode.** `share/yosys/gowin/brams_map.v`
  hardcodes `.READ_MODE(1'b0)` on every BSRAM it emits, and `brams.txt` has no
  output-register option at all, so a register written next to the memory read in the RTL
  stays a fabric flip-flop and is never absorbed into the BSRAM. Bypass is the slowest read
  arc and, per the point above, the untimed one. Instantiate `SDPB`/`SDPX9B`/`DPB` yourself
  with `READ_MODE=1` if you want the internal output register.
- **A 1R1W memory infers as `DP`, not `SDP`.** In `share/yosys/gowin/brams.txt`
  `$__GOWIN_DP_` and `$__GOWIN_SDP_` both cost 128 and both offer the 18-bit width, and
  `DP` is listed first, so the tie goes to `DP`. There is no attribute for this; instantiate
  the primitive if you need semi-dual-port. Note also that `DP` offers only
  `WRITE_MODE` 0 (no change) and 1 (new): unlike `SP` it has no read-first mode, so Verilog
  that reads the old value at a written address is not guaranteed in silicon.
- **To keep a ROM out of BSRAM, `ram_style`, `rom_style` and `logic_block` all work;
  `"distributed"` does not.** On the 492 x 188-bit control ROM in
  `benchmarks/mlkem-ntt/work/mlkem-ntt-l4-p162/mlkem_ntt_core.v`,
  `(* ram_style = "logic" *)` on the `reg` declaration took it from 6 `SPX9` to none, at
  +1869 `LUT4` and +1464 `MUX2_LUT5`. `(* rom_style = "logic" *)` and `(* logic_block *)`
  give byte-identical results. `(* ram_style = "distributed" *)` fails with
  `ERROR: no valid mapping found for memory`, because `lutrams.txt` sets `prune_rom` and so
  LUT RAM is never offered to a read-only memory. Verify the result by counting `SP`/`SPX9`
  cells in the `_build` JSON, not by reading the `BSRAM` line in `apio report`, which counts
  every block RAM in the design.

## What has not been tried

- `apio upload`. All programming so far used `openFPGALoader` directly.
- `apio sim` (graphical waveforms), `apio lint`, `apio format`. `apio test` and `apio report` were used on `projects/stoplight/`.
- Writing anything to flash. The board's original flash contents are backed up in `reference/tang-nano-20k-flash/`, and only SRAM has been written.
- Restoring that backup.
- `rx` on pin 70.
- The Gowin vendor IDE. It is not installed and not needed for anything so far.

## Flash backup

`reference/tang-nano-20k-flash/tang20k-flash-8M.bin`, dumped with:

```
openFPGALoader --dump-flash --file-size 8388608 -o 0 tang20k-flash-8M.bin
```

SHA-256 `e5bf8c5b7c6c89cd23fcf594fbf8487d1c2802229c2eb83cb78460083018a139`. One Gowin bitstream at offset 0, ending at `0xDD88F`. The rest is `0xFF`. It boots a LiteX SoC (VexRiscv at 48 MHz, 8 MiB SDRAM, BIOS built 2023-03-13).

## Disk use

`/home` was at 5.9 GB free before this was set up and 3.3 GB after. Almost all of that is `~/.apio`.

## Removing everything

```
rm -rf .venv ~/.apio /mnt/sdd1/victor-apio
sudo rm /etc/udev/rules.d/99-fpga.rules && sudo udevadm control --reload
```

Nothing else needs undoing.
