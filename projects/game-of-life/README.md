# game-of-life

Conway's Game of Life on HDMI: a 160 x 90 torus, 8 x 8 pixels per cell, 1280x720 @ 60 Hz, one generation every 4 frames (15 per second). No vendor IP.

## What you see

- Live cells in one colour on a dark blue-grey field, with a dark line between cells. The live colour changes every 64 generations.
- A random soup (about 37% alive) is generated on power-up. The generation speed on screen is set by `FRAMES_PER_GEN` in `top.v`; the engine itself is far faster than the 60 Hz display. When the grid stops changing, or after 1024 generations, a new soup replaces it.
- LEDs (active low): `leds[0]` lit when the PLL is locked, `leds[5:1]` are the low five bits of the generation count.

## How it works

`life_row_core.v` updates a whole row of 160 cells every clock. Each buffer is 90 rows of 160 bits in block RAM, one row per word. A generation streams rows 89, 0, 1, ..., 89, 0 out of the front buffer through a 3-row window; once the window is full, the 3 x 160 neighbourhood produces a complete new row each clock, which is written to the back buffer. A generation takes **96 clocks** (H + 6), which is 1.3 us at 74.25 MHz, or about 11 billion cell updates per second. Edges wrap.

The engine runs in the vertical blanking interval (it starts at line 720), and the buffers swap as soon as the last row is written, so the picture never tears. The display and the engine share the RAM's one read port. During each line's horizontal blanking the display reads the row for the next line into a 160-bit shift register, which steps one cell every 8 pixels.

The first version, `life_core.v`, does one cell at a time (12 clocks per cell, 173k clocks per generation, 2.3 ms). It is still here, with its own testbench, as the simple baseline. `top.v` uses the row-parallel core.

| File | What |
|---|---|
| `life_row_core.v` | The row-parallel engine, buffers and seeding. Plain Verilog, simulates. Used by `top.v`. |
| `life_core.v` | The one-cell-at-a-time engine. Not used by `top.v`. |
| `top.v` | Clocks, pacing, row prefetch, colours, serializers. In `ifdef SYNTHESIZE` for the Gowin primitives. |
| `life_row_core_tb.v`, `life_core_tb.v` | A 16 x 8 torus run through 130 generations and several reseeds, each compared with a plain-loop reference. The row-core one also checks the display port and that a generation takes H + 6 clocks. |
| `tmds_encoder.v`, `video_timing.v` and their testbenches, `pins.cst` | Copied from `hdmi-test`. |

## Test and build

```
source ../../env.sh
apio test        # four testbenches print PASS
apio build
openFPGALoader -c ft2232 _build/default/hardware.fs
```

Both core testbenches were checked against deliberately broken copies (wrap-around of x, a wrong survive rule, a window that does not shift); each prints `FAIL`.

Build result (row-parallel): 5 of 46 block RAMs, 3144 LUT4, 1433 DFF. nextpnr reports pclk at 161 MHz against the 74.25 MHz needed. The one-cell-at-a-time version used 8 block RAMs, 475 LUT4 and 189 MHz.

## Notes

- `apio report` crashes with a division by zero on this design (its table has `IOLOGIC_DUMMY` with 0 available). Read `_build/default/hardware.pnr` instead.
- Simulation shows the logic is right. It does not show what the monitor displays; that needs a person looking at the screen.
