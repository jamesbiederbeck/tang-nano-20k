#!/usr/bin/env python3
"""Synthesize, place and route one generated project and record area and timing.

Runs the same three tools apio runs (yosys synth_gowin, nextpnr-himbaechel, gowin_pack)
but with an explicit nextpnr --freq target and --seed, and writes a JSON record:
utilisation, post-route fmax per clock, tool versions, git revisions.
Usage: synth.py <project-dir> [--freq MHZ] [--seed N] [--noalu] [--out file.json] [--pack]
Needs the toolchain on PATH (source env.sh).
"""
import argparse, json, re, subprocess, sys, time
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("project", type=Path)
ap.add_argument("--freq", type=float, default=27.0)
ap.add_argument("--seed", type=int, default=1)
ap.add_argument("--noalu", action="store_true")
ap.add_argument("--out", type=Path)
ap.add_argument("--pack", action="store_true", help="also write the bitstream")
ap.add_argument("--allow-fail", action="store_true", help="nextpnr --timing-allow-fail")
a = ap.parse_args()
d = a.project.resolve()
work = d / "_build" / "bench"
work.mkdir(parents=True, exist_ok=True)


def sh(cmd, log):
    t = time.time()
    r = subprocess.run(cmd, shell=True, cwd=d, capture_output=True, text=True)
    (work / log).write_text(r.stdout + r.stderr)
    return r.returncode, time.time() - t, r.stdout + r.stderr


def ver(cmd):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return (r.stdout + r.stderr).strip().splitlines()[0] if (r.stdout + r.stderr).strip() else "?"


def git(repo):
    r = subprocess.run(f"git -C {repo} rev-parse --short HEAD", shell=True, capture_output=True, text=True)
    return r.stdout.strip() or "?"


vfiles = " ".join(p.name for p in sorted(d.glob("*.v")) if not p.name.endswith("_tb.v"))
top = re.search(r"top-module\s*=\s*(\S+)", (d / "apio.ini").read_text()).group(1)
ys = f'yosys -q -p "synth_gowin -top {top} -family gw2a {"-noalu " if a.noalu else ""}-json _build/bench/hw.json" -DSYNTHESIZE {vfiles}'
rc, ts, _ = sh(ys, "yosys.log")
if rc:
    sys.exit("yosys failed; see " + str(work / "yosys.log"))
pnr = (f"nextpnr-himbaechel --device GW2AR-LV18QN88C8/I7 --json _build/bench/hw.json "
       f"--write _build/bench/hw.pnr.json --vopt family=GW2A-18C --vopt cst=pins.cst "
       f"--freq {a.freq} --seed {a.seed}" + (" --timing-allow-fail" if a.allow_fail else ""))
rc, tp, log = sh(pnr, "nextpnr.log")

util = {}
for m in re.finditer(r"Info:\s+(\w+):\s+(\d+)/\s*(\d+)\s+(\d+)%", log):
    util[m.group(1)] = dict(used=int(m.group(2)), avail=int(m.group(3)))
fmax = [(m.group(1), float(m.group(2)), m.group(3)) for m in
        re.finditer(r"Max frequency for clock\s+'([^']+)':\s+([\d.]+) MHz \((PASS|FAIL) at", log)]
post = {}
for name, f, status in fmax:                     # the last report per clock is post-route
    post[name] = dict(fmax_mhz=f, status=status)
holds = re.search(r"(\d+) Hold/min time violations", log)
res = dict(
    project=d.name, top=top, freq_target_mhz=a.freq, seed=a.seed, noalu=a.noalu,
    nextpnr_exit=rc, hold_violations=int(holds.group(1)) if holds else 0,
    utilisation=util, clocks=post,
    seconds=dict(yosys=round(ts, 1), nextpnr=round(tp, 1)),
    tools=dict(yosys=ver("yosys -V"), nextpnr=ver("nextpnr-himbaechel --version 2>&1"),
               gowin_pack=ver("pip show apycula 2>/dev/null | grep Version || echo apycula")),
    git=dict(generator=git(Path.home() / "code/cook_mertz"), project_repo=git(d)),
    generated_txt=(d / "GENERATED.txt").read_text() if (d / "GENERATED.txt").exists() else None,
    when=time.strftime("%Y-%m-%d %H:%M:%S"))
if a.pack and rc == 0:
    rc2, _, _ = sh(f"gowin_pack -d GW2A-18C -o _build/bench/hw.fs _build/bench/hw.pnr.json", "pack.log")
    res["bitstream"] = str(work / "hw.fs") if rc2 == 0 else None
print(json.dumps(res, indent=1))
if a.out:
    a.out.write_text(json.dumps(res, indent=1))
sys.exit(0 if rc == 0 else 1)
