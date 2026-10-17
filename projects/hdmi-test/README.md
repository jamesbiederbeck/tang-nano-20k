# hdmi-test

A 1280x720 @ 60 Hz HDMI (DVI) test pattern on the Tang Nano 20K, with no vendor IP. Confirmed working on a monitor.

## What you see

- Top 40 lines: a white 32-pixel marker that moves 8 pixels per frame, so a frozen picture is obvious.
- Middle: eight vertical colour bars (white, yellow, cyan, green, magenta, red, blue, black).
- Bottom 120 lines: a black-to-white grey ramp.
- LEDs (active low): `leds[0]` lit when the PLL is locked, `leds[5:1]` count frames.

## How it works

```
27 MHz crystal -> rPLL (x55/4 = 371.25 MHz) -> CLKDIV /5 -> 74.25 MHz pixel clock
pixel clock -> video_timing -> pattern -> 3 x tmds_encoder -> 3 x OSER10 (10:1) -> TLVDS_OBUF -> HDMI
```

| File | What |
|---|---|
| `top.v` | Clocks, serializers and differential outputs. Wrapped in `ifdef SYNTHESIZE` because the simulator has no Gowin primitives. |
| `tmds_encoder.v` | TMDS 8b/10b encoder from the DVI 1.0 spec. Control symbols during blanking, no data islands, so it is plain DVI. |
| `video_timing.v` | CEA-861 720p60 counters and sync pulses. |
| `pattern.v` | The picture. |
| `tmds_encoder_tb.v` | Decodes every byte plus 1500 random ones back and checks the symbol balance and control codes. |
| `video_timing_tb.v` | Checks clocks per frame, active pixels and sync widths over three frames. |
| `pins.cst` | HDMI on pins 33 to 40 (from Sipeed's `TangNano-20K-example`), LEDs on 15 to 20. |

## Test and build

```
source ../../env.sh
apio test        # both testbenches print PASS
apio build
openFPGALoader -c ft2232 _build/default/hardware.fs
```

## Notes

- Sipeed's own HDMI example uses Gowin's closed DVI IP, which does not work in the open-source flow. The pin numbers and the PLL settings (IDIV 3, FBDIV 54, ODIV 2) come from it. The encoder and timing were written here.
- `pins.cst` lists each differential pin separately. nextpnr does not accept Gowin's `33,34` pair syntax.
- The pins use `IO_TYPE=LVDS25` without `BANK_VCCIO=3.3`. With `BANK_VCCIO=3.3` added, `gowin_pack` stops with "Conflict bank VCC". The board supplies 3.3 V to that bank either way. We do not know if this affects signal quality; the picture was stable on the monitor we tried.
- nextpnr runs against a 12 MHz target here. The pixel clock reached 82.8 MHz against the 74.25 MHz needed, so there is about 11% headroom.
