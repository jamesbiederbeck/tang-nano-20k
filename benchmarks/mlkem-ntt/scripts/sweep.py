#!/usr/bin/env python3
"""Build, route, (optionally) load and board-test one or more accelerator variants.

  sweep.py l4:p100.29 l2:p120 l1:crystal ...        variant = l<lanes>:<clock>[:<opts>]
  clock    crystal | p<MHz> (nearest rPLL setting from PLL_TABLE)
  opts     barrett | lut (bank RAM) | noalu | x0w0 (no crossbar registers)
  --board  load each bitstream to SRAM and run board_test.py (needs the board; nothing is flashed)
Each variant writes results/<name>.synth.json and, with --board, results/<name>.board.json.
Generated projects live in work/ (git-ignored); the committed copies are under projects/.
"""
import argparse, json, os, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH = HERE.parent
CMTZ = Path(os.environ.get("CMTZ_REPO", Path.home() / "code/cook_mertz"))
# core clock = 27 MHz * (FBDIV+1) / (IDIV+1); VCO = clock * ODIV must be 500..1250 MHz
PLL_TABLE = {
    54: (0, 1, 16), 81: (0, 2, 8), 100.29: (6, 25, 8), 108: (0, 3, 8), 120: (8, 39, 8),
    135: (0, 4, 4), 150: (8, 49, 4), 162: (0, 5, 4), 180: (0, 6, 4), 189: (0, 6, 4),
    171: (2, 18, 4), 200: (4, 36, 4), 216: (0, 7, 4), 243: (0, 8, 2),
}
PLL_TABLE[189] = (0, 6, 4)       # replaced below; 189 = 27*7 needs FBDIV 6 (x7)
PLL_TABLE[180] = (2, 19, 4)      # 27*20/3 = 180
PLL_TABLE[162] = (0, 5, 4)       # 27*6
PLL_TABLE[216] = (0, 7, 4)       # 27*8
PLL_TABLE[243] = (0, 8, 2)       # 27*9


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=True, text=True, capture_output=True, **kw)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("variants", nargs="+")
    ap.add_argument("--board", action="store_true")
    ap.add_argument("--margin", type=float, default=1.0, help="nextpnr target = clock * margin")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--reps", type=int, default=200)
    ap.add_argument("--vectors", type=int, default=0, help="extra random polynomials for board_test")
    a = ap.parse_args()
    (BENCH / "results").mkdir(exist_ok=True)
    (BENCH / "work").mkdir(exist_ok=True)
    for v in a.variants:
        parts = v.split(":")
        lanes = int(parts[0][1:])
        clk = parts[1]
        opts = set(parts[2:])
        pll = None
        mhz = 27.0
        if clk != "crystal":
            mhz = float(clk[1:])
            pll = PLL_TABLE[min(PLL_TABLE, key=lambda k: abs(k - mhz))]
            mhz = 27.0 * (pll[1] + 1) / (pll[0] + 1)
        name = f"l{lanes}-" + ("crystal" if pll is None else f"p{mhz:.0f}") + "".join("-" + o for o in sorted(opts))
        cmd = (f"uv run --project {CMTZ} python {CMTZ}/examples/fpga/build_mlkem_ntt.py {BENCH / 'work'} "
               f"--lanes {lanes} --suffix {name.split('-', 1)[1] or 'x'}"
               + (f" --pll {','.join(map(str, pll))}" if pll else "")
               + (" --reduction barrett" if "barrett" in opts else "")
               + (" --bank-ram lut" if "lut" in opts else "")
               + (" --noalu" if "noalu" in opts else "")
               + (" --xreg0" if "x0w0" in opts else "")
               + (" --lane swap" if "swap" in opts else "")
               + (" --rom-ram logic" if "romlogic" in opts else "")
               + (" --bank-prim sdp" if "sdp" in opts else "")
               + "".join(f" --{o[:-1] if o[:-1] in ('rd-reg',) else o[:-1]} {o[-1]}" for o in opts if o[:-1] in ("rd-reg", "rom-reg", "bin-reg")))
        r = sh(cmd)
        if r.returncode:
            print(r.stdout, r.stderr); sys.exit(f"generation failed for {v}")
        proj = Path(r.stdout.strip().splitlines()[-1])
        print(f"== {name}: {proj.name} @ {mhz:.2f} MHz", flush=True)
        if a.seed != 1:
            name += f"-s{a.seed}"
        out = BENCH / "results" / f"{name}.synth.json"
        s = sh(f"python3 {HERE}/synth.py {proj} --freq {mhz * a.margin} --seed {a.seed} --pack --allow-fail --out {out}"
               + (" --noalu" if "noalu" in opts else ""))
        if s.returncode:
            print(f"   route FAILED (see {proj}/_build/bench/nextpnr.log)")
            continue
        j = json.loads(out.read_text())
        u = {k: j["utilisation"][k]["used"] for k in ("LUT4", "ALU", "DFF", "BSRAM", "MULT18X18") if k in j["utilisation"]}
        print("   ", u, {k: (c["fmax_mhz"], c["status"]) for k, c in j["clocks"].items()}, flush=True)
        if a.board:
            fs = proj / "_build/bench/hw.fs"
            l = sh(f"openFPGALoader -c ft2232 {fs}")
            if l.returncode:
                print("   load failed", l.stdout[-300:], l.stderr[-300:]); continue
            time.sleep(1.5)
            b = sh(f"python3 -I {HERE}/board_test.py --label {name} --reps {a.reps} --vectors {a.vectors} --out {BENCH / 'results' / (name + '.board.json')}")
            print("   board:", [ln for ln in b.stdout.splitlines() if "mismatch" in ln or "clock" in ln or "back-to-back" in ln])


main()
