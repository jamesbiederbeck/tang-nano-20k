#!/usr/bin/env python3
"""Turn results/*.board.json (+ matching .synth.json) into a markdown table.
Latency = on-chip kernel cycles / core clock measured on chip. Rows with mismatches are
marked FAIL and carry no latency claim."""
import json, sys
from pathlib import Path

res = Path(__file__).resolve().parent.parent / "results"
PAPER = dict(fwd_us=5.145, inv_us=6.425)
rows = []
for bj in sorted(res.glob("*.board.json")):
    b = json.loads(bj.read_text())
    sj = res / bj.name.replace(".board.json", ".synth.json")
    s = json.loads(sj.read_text()) if sj.exists() else {}
    u = {k: v["used"] for k, v in s.get("utilisation", {}).items()}
    khz = b.get("core_clock_khz")
    ok = b["mismatches"] == 0 and b["forward_cycles"]
    fc = b["forward_cycles"][0] if b["forward_cycles"] else None
    ic = b["inverse_cycles"][0] if b["inverse_cycles"] else None
    fmax = {k: c for k, c in s.get("clocks", {}).items() if k == "fclk"}.get("fclk", {})
    rows.append((bj.stem.replace(".board", ""), b["lanes"], b["reduction"], khz, fc, ic, ok,
                 b["polynomials"], b["mismatches"], fmax.get("fmax_mhz"), fmax.get("status"),
                 u.get("LUT4"), u.get("ALU"), u.get("DFF"), u.get("BSRAM"), u.get("MULT18X18"),
                 b.get("back_to_back_clocks"), b.get("back_to_back_reps")))
print("| run | lanes | red. | clock MHz | fwd cyc | inv cyc | fwd us | inv us | fwd/s | polys | mism. | nextpnr fmax (not BSRAM-timed) | LUT4 | ALU | FF | BSRAM | DSP |")
print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
for r in rows:
    (n, L, red, khz, fc, ic, ok, polys, mm, fm, fst, lut, alu, ff, bs, dsp, b2b, reps) = r
    mhz = khz / 1000 if khz else None
    fu = f"{fc / mhz:.3f}" if ok and mhz and fc else "FAIL"
    iu = f"{ic / mhz:.3f}" if ok and mhz and ic else "FAIL"
    tp = f"{reps * khz * 1e3 / b2b:,.0f}" if ok and b2b and reps and khz else "-"
    print(f"| {n} | {L} | {red[:4]} | {mhz:.2f} | {fc} | {ic} | {fu} | {iu} | {tp} | {polys} | {mm} | "
          f"{fm} {fst} | {lut} | {alu} | {ff} | {bs} | {dsp} |")
