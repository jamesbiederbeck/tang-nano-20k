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

Pin map for the rest of the board is on the Sipeed wiki. A pin diagram image from the Amazon listing was used for the LED pins.

## Things that went wrong

- **`openFPGALoader -b tangnano20k` found no device** during the first attempt. At that time the JTAG chain was not answering at all, so the board preset was not the cause. `-c ft2232` works.
- **JTAG stopped answering for a while.** `--detect` found the GW2A-18 once, then printed an empty chain for several attempts. A USB reset (`USBDEVFS_RESET`) and the `ftdi_sio` unbind did not fix it. Unplugging the board and plugging it back in did. The cause is unknown.
- **Do not trust the line `empty` in openFPGALoader output.** It prints on every run, including successful ones. Look for the `idcode` line.
- **`openFPGALoader` needs the udev rule.** Without it, it fails with "Access denied (insufficient permissions)".
- **Hand-written Verilog off-by-one.** The first `hello.v` declared its message 28 bytes wide for a 27-byte string, which would have sent a stray `0x00` first. Fixed before the first load.

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
