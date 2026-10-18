#!/usr/bin/env python3
"""Draw the hand-made overview diagrams into docs/diagrams/*.svg.

The SVGs use plain shapes and text with inline attributes only (no CSS, no external fonts, no scripts),
so GitHub shows them the same on the website and in the mobile app. Each has its own white background,
because GitHub draws an SVG as an image, which does not follow the page's dark mode.

Run:  python3 scripts/draw_diagrams.py
"""
import math
import os

INK, TEAL, SOFT, MUTED, RULE, BG = "#1b2a2d", "#0b7a75", "#d9efec", "#5b6d70", "#c9d4d2", "#ffffff"
FONT = 'ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace'
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "diagrams")


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


class Box:
    def __init__(self, x, y, w, h):
        self.x, self.y, self.w, self.h = x, y, w, h

    def l(self, dy=None): return (self.x, self.y + (self.h / 2 if dy is None else dy))
    def r(self, dy=None): return (self.x + self.w, self.y + (self.h / 2 if dy is None else dy))
    def t(self, dx=None): return (self.x + (self.w / 2 if dx is None else dx), self.y)
    def b(self, dx=None): return (self.x + (self.w / 2 if dx is None else dx), self.y + self.h)


class Svg:
    def __init__(self, w, h, title, desc):
        self.w, self.h, self.title, self.desc = w, h, title, desc
        self.p = []

    def text(self, x, y, s, size=12, weight="normal", fill=INK, anchor="start", halo=False):
        extra = f' stroke="{BG}" stroke-width="4" stroke-linejoin="round" paint-order="stroke"' if halo else ""
        self.p.append(f'<text x="{x:.1f}" y="{y:.1f}" font-family=\'{FONT}\' font-size="{size}" '
                      f'font-weight="{weight}" fill="{fill}" text-anchor="{anchor}"{extra}>{esc(s)}</text>')

    def label(self, x, y, s, anchor="middle", size=11, fill=MUTED):
        """Small text with a white backing rectangle so a wire never runs through it."""
        w = len(s) * size * 0.6 + 6
        left = x - w / 2 if anchor == "middle" else (x - w + 3 if anchor == "end" else x - 3)
        self.p.append(f'<rect x="{left:.1f}" y="{y - size:.1f}" width="{w:.1f}" height="{size + 5}" fill="{BG}" stroke="none"/>')
        self.text(x, y, s, size, "normal", fill, anchor)

    def line(self, x1, y1, x2, y2, stroke=RULE, width=1, dash=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.p.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{stroke}" stroke-width="{width}"{d}/>')

    def frame(self, x, y, w, h, label):
        self.p.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="none" stroke="{MUTED}" stroke-width="1.2" stroke-dasharray="5 4"/>')
        self.text(x + 10, y - 7, label, 12, "bold", MUTED)

    def box(self, x, y, title, lines=(), kind="blk", w=None, h=None):
        tw = max([len(title) * 8.6] + [len(s) * 7.3 for s in lines]) + 30
        w = w or max(tw, 96)
        h = h or (22 + 18 * (1 + len(lines)) if lines else 44)
        fill, stroke, dash = {"blk": (BG, INK, ""), "io": (SOFT, TEAL, ""), "off": (BG, MUTED, "5 3")}[kind]
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.p.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="3" fill="{fill}" stroke="{stroke}" stroke-width="1.6"{d}/>')
        ty = y + 23
        self.text(x + 14, ty, title, 14, "bold", TEAL if kind == "io" else INK)
        for i, s in enumerate(lines):
            self.text(x + 14, ty + 19 * (i + 1), s, 12, "normal", MUTED)
        return Box(x, y, w, h)

    def arrow(self, pts, label=None, lpos=None, kind="ink", dashed=False, both=False, head=8):
        col = {"ink": INK, "acc": TEAL, "muted": MUTED}[kind]
        wd = 2.2 if kind == "acc" else 1.6
        d = ' stroke-dasharray="4 3"' if dashed else ""
        pl = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
        self.p.append(f'<polyline points="{pl}" fill="none" stroke="{col}" stroke-width="{wd}" stroke-linejoin="round"{d}/>')

        def tip(p_from, p_to):
            ang = math.atan2(p_to[1] - p_from[1], p_to[0] - p_from[0])
            bx, by = p_to[0] - head * math.cos(ang), p_to[1] - head * math.sin(ang)
            nx, ny = -math.sin(ang) * head * 0.45, math.cos(ang) * head * 0.45
            self.p.append(f'<polygon points="{p_to[0]:.1f},{p_to[1]:.1f} {bx + nx:.1f},{by + ny:.1f} {bx - nx:.1f},{by - ny:.1f}" fill="{col}"/>')
        tip(pts[-2], pts[-1])
        if both:
            tip(pts[1], pts[0])
        if label:
            if lpos is None:
                (x1, y1), (x2, y2) = pts[0], pts[1]
                if abs(y1 - y2) < 1:
                    lpos, anchor = ((x1 + x2) / 2, y1 - 7), "middle"
                else:
                    lpos, anchor = (x1 + 7, (y1 + y2) / 2 + 4), "start"
            else:
                anchor = "middle"
            self.label(lpos[0], lpos[1], label, anchor)

    def tag(self, x, y, label):
        """A clock net label: short arrow down into (x, y) with the name above it."""
        self.arrow([(x, y - 22), (x, y)], head=6)
        self.text(x, y - 27, label, 11, "normal", TEAL, "middle")

    def bus_mark(self, x, y, n):
        self.line(x - 4, y + 6, x + 4, y - 6, INK, 1.4)
        self.text(x + 6, y - 9, str(n), 11, "normal", MUTED)

    def inverter(self, x, y, h=34):
        self.p.append(f'<polygon points="{x:.1f},{y - h / 2:.1f} {x:.1f},{y + h / 2:.1f} {x + 36:.1f},{y:.1f}" fill="{BG}" stroke="{INK}" stroke-width="1.6"/>')
        self.p.append(f'<circle cx="{x + 41:.1f}" cy="{y:.1f}" r="5" fill="{BG}" stroke="{INK}" stroke-width="1.6"/>')
        return (x, y), (x + 46, y)

    def section(self, x, y, s, x2):
        self.text(x, y, s.upper(), 12, "bold", MUTED)
        self.line(x, y + 8, x2, y + 8, RULE)

    def lamp(self, cx, cy, color, lit, r=9):
        fill = color if lit else "#e6ebea"
        stroke = INK if lit else "#b9c4c2"
        self.p.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="1.4"/>')

    def save(self, name):
        os.makedirs(OUT, exist_ok=True)
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" width="{self.w}" height="{self.h}" role="img" aria-label="{esc(self.desc)}">\n'
               f'<title>{esc(self.title)}</title>\n'
               f'<rect x="0" y="0" width="{self.w}" height="{self.h}" fill="{BG}"/>\n'
               + "\n".join(self.p) + "\n</svg>\n")
        path = os.path.join(OUT, name)
        open(path, "w").write(svg)
        print("wrote", os.path.normpath(path))


# ------------------------------------------------------------------ root README
def toolchain():
    s = Svg(1180, 380, "Tool flow",
            "Verilog and pins.cst go through yosys, nextpnr and gowin_pack to a bitstream that openFPGALoader writes to the FPGA's SRAM or its SPI flash. The same Verilog plus a testbench run in simulation with apio test.")
    v = s.box(20, 110, "Verilog", ["*.v"], w=150)
    y = s.box(260, 110, "yosys", ["synth_gowin"], w=150)
    n = s.box(500, 110, "nextpnr", ["place and route"], w=150)
    g = s.box(740, 110, "gowin_pack", ["bitstream"], w=150)
    o = s.box(980, 110, "openFPGALoader", ["JTAG"], w=180)
    pins = s.box(500, 14, "pins.cst", ["pin numbers"], w=150)
    s.frame(240, 96, 670, 90, "apio build")
    s.arrow([v.r(), y.l()])
    s.arrow([y.r(), n.l()], "json")
    s.arrow([n.r(), g.l()], "placed")
    s.arrow([g.r(), o.l()], ".fs")
    s.arrow([pins.b(), n.t()])
    sram = s.box(880, 270, "FPGA SRAM", ["gone on power cycle"], "io", w=180)
    flash = s.box(1075, 270, "SPI flash", ["persists"], "io", w=100)
    s.arrow([(1000, o.y + o.h), sram.t(120)], "load", kind="acc")
    s.arrow([(1130, o.y + o.h), flash.t(55)], "-f", kind="acc")
    tb = s.box(20, 270, "testbench", ["*_tb.v"], w=150)
    sim = s.box(260, 270, "apio test", ["iverilog, no board"], w=210)
    s.arrow([(95, v.y + v.h), (95, 230), (365, 230), (365, 270)])
    s.arrow([tb.r(), sim.l()])
    s.save("toolchain.svg")


def board():
    s = Svg(980, 440, "The board as the PC sees it",
            "The PC connects over USB-C to the BL616 debugger, which gives the FPGA a JTAG link and a UART. The 27 MHz crystal and the SPI flash connect to the FPGA, which drives six LEDs and the HDMI output.")
    pc = s.box(20, 147, "PC", ["Linux"], w=110)
    bl = s.box(190, 138, "BL616 debugger", ["shows up as an FT2232", "USB id 0403:6010"], w=214)
    fpga = s.box(530, 120, "GW2AR-18 FPGA", ["20736 LUT4", "48 multipliers"], "blk", w=190, h=150)
    led = s.box(530, 10, "6 LEDs", ["active low"], "io", w=190)
    hdmi = s.box(530, 340, "HDMI output", ["pins 33 to 40"], "io", w=190)
    xtal = s.box(800, 140, "27 MHz crystal", ["pin 4"], w=170)
    flash = s.box(800, 216, "SPI flash", ["64 Mbit, bitstream"], w=170)
    s.arrow([pc.r(), bl.l(bl.h / 2 + 0)], "USB-C", both=True)
    s.arrow([bl.r(160 - 138), (fpga.x, 160)], "JTAG, ch A", both=True)
    s.arrow([bl.r(196 - 138), (fpga.x, 200)], "UART, ch B", both=True)
    s.label(467, 216, "tx 69, rx 70")
    s.arrow([xtal.l(), (fpga.x + fpga.w, xtal.l()[1])])
    s.arrow([flash.l(), (fpga.x + fpga.w, 245)], both=True)
    s.arrow([(625, fpga.y), led.b(95)], "pins 15 to 20", kind="acc", lpos=(667, 98))
    s.arrow([(625, fpga.y + fpga.h), hdmi.t(95)], "", kind="acc")
    s.save("board.svg")


# ------------------------------------------------------------------ blink
def blink():
    s = Svg(780, 170, "blink",
            "The 27 MHz clock drives a 25-bit counter. Bits 24 down to 19 pass through inverters to the six active-low LEDs.")
    clk = s.box(20, 46, "clk", ["pin 4", "27 MHz"], "io", w=120, h=76)
    cnt = s.box(190, 40, "count", ["25-bit register", "+1 every clock"], w=190, h=88)
    s.arrow([clk.r(), (cnt.x, clk.y + clk.h / 2)])
    yb = 84
    s.arrow([(cnt.x + cnt.w, yb), (466, yb)])
    s.bus_mark(425, yb, 6)
    s.text(425, yb + 24, "count[24:19]", 11, "normal", MUTED, "middle")
    (ix, iy), (ox, oy) = s.inverter(468, yb)
    s.text(490, yb + 40, "NOT x6", 11, "normal", MUTED, "middle")
    s.arrow([(ox + 4, oy), (590, oy)], kind="acc")
    s.bus_mark(552, oy, 6)
    s.box(590, 46, "leds[5:0]", ["pins 15 to 20", "active low"], "io", w=170, h=76)
    s.save("blink.svg")


# ------------------------------------------------------------------ hello
def hello():
    s = Svg(960, 530, "hello",
            "Path A: the clock drives a 27-bit counter whose top six bits are inverted onto the LEDs. Path B: a one-second timer starts a state machine that reads 27 message bytes from a ROM into a 10-bit shift register clocked by a baud divider, through a flip-flop to pin 69 and the BL616 bridge to the PC.")
    s.section(20, 28, "A · counter to LEDs", 940)
    clk = s.box(20, 46, "clk", ["pin 4", "27 MHz"], "io", w=110, h=76)
    cnt = s.box(180, 40, "count", ["27-bit register"], w=180, h=88)
    s.arrow([clk.r(), (cnt.x, 84)])
    s.arrow([(360, 84), (456, 84)])
    s.bus_mark(408, 84, 6)
    s.text(408, 108, "count[26:21]", 11, "normal", MUTED, "middle")
    (ix, iy), (ox, oy) = s.inverter(458, 84)
    s.arrow([(ox + 4, oy), (570, oy)], kind="acc")
    s.bus_mark(535, oy, 6)
    s.box(570, 46, "leds[5:0]", ["pins 15 to 20", "active low"], "io", w=170, h=76)

    s.section(20, 170, "B · UART greeting, 115200 baud 8N1", 940)
    s.text(940, 196, "clk drives every register in this section", 11, "normal", MUTED, "end")
    r1, h1 = 215, 94
    timer = s.box(20, r1, "timer", ["25-bit counter", "= 26 999 999"], w=150, h=h1)
    fsm = s.box(210, r1, "state", ["3-bit machine", "0 gap  1 load", "2 send  3 next"], w=150, h=h1)
    shf = s.box(400, r1, "shifter", ["10-bit register", "{1, byte, 0}"], w=150, h=h1)
    txr = s.box(590, r1, "tx", ["flip-flop"], w=150, h=h1)
    pin = s.box(780, r1, "tx pin", ["pin 69"], "io", w=150, h=h1)
    cy = r1 + h1 / 2
    s.arrow([timer.r(), (fsm.x, cy)], "go")
    s.arrow([fsm.r(), (shf.x, cy)], "load")
    s.arrow([shf.r(), (txr.x, cy)], "[0]")
    s.arrow([txr.r(), (pin.x, cy)], kind="acc")
    s.arrow([(300, 190), (300, r1)], head=6)
    s.text(300, 184, "bit_tick", 11, "normal", TEAL, "middle")
    s.arrow([(475, 190), (475, r1)], head=6)
    s.text(475, 184, "bit_tick", 11, "normal", TEAL, "middle")

    r2 = 380
    div = s.box(20, r2, "baud divider", ["16-bit counter", "= 233, 27 MHz / 234"], w=190, h=76)
    idx = s.box(250, r2, "idx", ["6-bit register", "0 to 26"], w=150, h=76)
    rom = s.box(440, r2, "message ROM", ["27 bytes"], w=170, h=76)
    s.arrow([(div.x + 95, r2 + 76), (div.x + 95, 490)], head=6)
    s.text(div.x + 105, 496, "bit_tick", 11, "normal", TEAL)
    s.arrow([(290, r1 + h1), (290, r2)], "inc")
    s.arrow([(360, r2), (360, r1 + h1)], "idx = 26")
    s.arrow([idx.r(), rom.l()], "addr")
    s.arrow([(520, r2), (520, r1 + h1 + 0)][0:1] + [(520, shf.y + shf.h)], "byte")
    s.text(440, 478, '"Hello from Tang Nano 20K!\\r\\n"', 12, "normal", TEAL)
    bl = s.box(780, r2, "BL616 bridge", ["to the PC", "/dev/ttyUSB1"], "off", w=150, h=76)
    s.arrow([(855, r1 + h1), (855, r2)], "UART", kind="acc")
    s.save("hello.svg")


# ------------------------------------------------------------------ stoplight
def stoplight():
    s = Svg(900, 460, "stoplight",
            "Six states in a loop: north-south green 5 seconds, north-south yellow 2, all red 1, east-west green 5, east-west yellow 2, all red 1. The cycle takes 16 seconds and starts in the last all-red state at power-up.")
    s.text(30, 34, "TWO-WAY INTERSECTION, 16 S PER CYCLE. BOTH DIRECTIONS ARE RED BETWEEN PHASES.", 12, "bold", MUTED)
    RED, YEL, GRN = "#d64533", "#e0a800", "#2e9460"
    states = [  # title, seconds, (NS lit), (EW lit)
        ("0 · NS green", "5 s", "G", "R"),
        ("1 · NS yellow", "2 s", "Y", "R"),
        ("2 · all red", "1 s", "R", "R"),
        ("3 · EW green", "5 s", "R", "G"),
        ("4 · EW yellow", "2 s", "R", "Y"),
        ("5 · all red", "1 s", "R", "R"),
    ]
    xs = [30, 325, 620]
    pos = [(xs[0], 60), (xs[1], 60), (xs[2], 60), (xs[2], 290), (xs[1], 290), (xs[0], 290)]
    boxes = []
    for (title, secs, ns, ew), (x, y) in zip(states, pos):
        b = s.box(x, y, title, [secs], "blk", w=250, h=116)
        boxes.append(b)
        for row, (lab, lit) in enumerate((("NS", ns), ("EW", ew))):
            ry = y + 68 + row * 26
            s.text(x + 14, ry + 4, lab, 12, "bold", MUTED)
            for k, (c, ch) in enumerate(((RED, "R"), (YEL, "Y"), (GRN, "G"))):
                s.lamp(x + 66 + k * 30, ry, c, lit == ch)
    cy = 60 + 58
    s.arrow([boxes[0].r(), boxes[1].l()])
    s.arrow([boxes[1].r(), boxes[2].l()])
    s.arrow([boxes[2].b(125), boxes[3].t(125)])
    cy2 = 290 + 58
    s.arrow([boxes[3].l(), boxes[4].r()])
    s.arrow([boxes[4].l(), boxes[5].r()])
    s.arrow([boxes[5].t(125), boxes[0].b(125)])
    s.text(30, 440, "State 5 is the power-up state, so the board starts all red.", 12, "normal", TEAL)
    s.save("stoplight.svg")


# ------------------------------------------------------------------ hdmi-test
def hdmi():
    s = Svg(980, 420, "hdmi-test",
            "The 27 MHz crystal feeds a PLL that makes a 371.25 MHz bit clock, divided by 5 into a 74.25 MHz pixel clock. Video timing and a test pattern feed three TMDS encoders, then four 10-to-1 serializers and differential output buffers to the HDMI connector.")
    s.section(20, 28, "clocks", 960)
    xt = s.box(20, 46, "27 MHz", ["crystal", "pin 4"], "io", w=150, h=76)
    pll = s.box(260, 46, "rPLL", ["27 x 55 / 4"], w=150, h=76)
    div = s.box(500, 46, "CLKDIV", ["divide by 5"], w=150, h=76)
    s.arrow([xt.r(), pll.l()])
    s.arrow([pll.r(), div.l()], "371.25 MHz")
    s.text(260, 142, "fclk = 371.25 MHz, to the serializers", 11, "normal", MUTED)
    s.text(500, 160, "pclk = 74.25 MHz, to all other logic", 11, "normal", MUTED)

    s.section(20, 200, "video", 960)
    y0, h = 250, 94
    vt = s.box(20, y0, "video_timing", ["x, y, de,", "hsync, vsync"], w=138, h=h)
    pt = s.box(180, y0, "pattern", ["bars, ramp,", "moving marker"], w=138, h=h)
    en = s.box(340, y0, "tmds_encoder", ["x 3: B, G, R", "8b to 10b"], w=138, h=h)
    se = s.box(500, y0, "OSER10", ["x 4, 10:1", "3 data + clock"], w=138, h=h)
    ob = s.box(660, y0, "TLVDS_OBUF", ["x 4", "differential"], w=138, h=h)
    hd = s.box(820, y0, "HDMI", ["pins 33 to 40"], "io", w=138, h=h)
    cy = y0 + h / 2
    for a, b in ((vt, pt), (pt, en), (en, se)):
        s.arrow([a.r(), b.l()])
    s.arrow([se.r(), ob.l()], kind="acc")
    s.arrow([ob.r(), hd.l()], kind="acc")
    for b in (vt, pt, en):
        s.tag(b.x + 100, y0, "pclk")
    s.tag(se.x + 40, y0, "fclk")
    s.tag(se.x + 100, y0, "pclk")
    s.arrow([(vt.x + 40, y0 + h), (vt.x + 40, y0 + h + 36), (en.x + 70, y0 + h + 36), (en.x + 70, y0 + h)], "de, hsync, vsync", lpos=(210, y0 + h + 30))
    s.save("hdmi-test.svg")


if __name__ == "__main__":
    for fn in (toolchain, board, blink, hello, stoplight, hdmi):
        fn()
