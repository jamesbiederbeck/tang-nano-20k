#!/usr/bin/env python3
"""Board test for the ML-KEM NTT accelerator (projects/mlkem-ntt-l*).

Loads polynomials over the UART, runs forward / inverse / round trip on the chip, reads
the result back and compares with the independent FIPS 203 oracle. Also reports:
  * kernel cycles from the on-chip counter ('F' / 'I' replies),
  * throughput from back-to-back transforms ('B'),
  * the core clock measured on chip against the 27 MHz crystal ('Q'),
  * UART transfer time (host wall clock), kept separate from the kernel time.
Usage: board_test.py [--cmtz PATH] [--out results.json] [--vectors N] [--reps N]
Only talks to the UART; load the bitstream first (openFPGALoader -c ft2232 hardware.fs).
"""
import argparse, glob, importlib.util, json, os, select, sys, termios, time

ap = argparse.ArgumentParser()
ap.add_argument("--cmtz", default=os.path.expanduser("~/code/cook_mertz"))
ap.add_argument("--out", default=None)
ap.add_argument("--vectors", type=int, default=0, help="extra random vectors beyond the fixed set")
ap.add_argument("--reps", type=int, default=100, help="back-to-back transforms for throughput")
ap.add_argument("--label", default="")
args = ap.parse_args()


def load(name):
    p = os.path.join(args.cmtz, "cmtz", "accel", "mlkem_ntt", name + ".py")
    spec = importlib.util.spec_from_file_location("mk_" + name, p)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m


O, V = load("fips203_oracle"), load("vectors")           # both are free-standing modules

port = glob.glob("/dev/serial/by-id/usb-SIPEED_USB_Debugger_*-if01-port0")[0]
fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
a = termios.tcgetattr(fd); a[0] = a[1] = a[3] = 0
a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL; a[4] = a[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, a)


def read(n, t):
    out = b""; end = time.time() + t
    while len(out) < n and time.time() < end:
        if select.select([fd], [], [], 0.02)[0]:
            out += os.read(fd, 4096)
    return out


# drain stale bytes: the debugger buffers old output
quiet = time.time(); drained = 0
while time.time() - quiet < 1.0:
    c = read(65536, 0.1)
    if c: drained += len(c); quiet = time.time()
print(f"drained {drained} stale bytes")

info = read(0, 0)
os.write(fd, b"P")
r = read(5, 1.0)
if r[:2] != b"MK" or len(r) != 5:
    sys.exit(f"no NTT accelerator answered: {r!r}")
lanes, red, ver = r[2], r[3], r[4]
print(f"accelerator: lanes={lanes} reduction={'barrett' if red else 'montgomery'} version={ver}")


def write_poly(f):
    t = time.time()
    buf = bytearray(b"W")
    for c in f: buf += bytes([c & 0xFF, c >> 8])
    os.write(fd, bytes(buf))
    ok = read(1, 3.0) == b"K"
    return ok, time.time() - t


def read_poly():
    t = time.time()
    os.write(fd, b"R")
    d = read(512, 3.0)
    dt = time.time() - t
    if len(d) != 512: return None, dt
    return [d[2 * i] | (d[2 * i + 1] << 8) for i in range(256)], dt


def run(cmd):
    t = time.time()
    os.write(fd, cmd)
    r = read(3, 2.0)
    dt = time.time() - t
    if len(r) != 3 or r[0:1] != b"K": return None, dt
    return r[1] | (r[2] << 8), dt


vecs = V.test_vectors(6 + args.vectors, seed=2026)
bad = 0; checks = 0; fwd_cycles = set(); inv_cycles = set(); xfer = []; wall = []
for name, f in vecs.items():
    ok, tw = write_poly(f); xfer.append(tw)
    cf, twall = run(b"F"); wall.append(twall)
    g, tr = read_poly(); xfer.append(tr)
    ef = O.ntt(f)
    checks += 1
    if not ok or cf is None or g != ef:
        bad += 1; print(f"MISMATCH forward {name}: cycles={cf}")
    else:
        fwd_cycles.add(cf)
    ci, _ = run(b"I")
    g2, _ = read_poly()
    checks += 1
    if ci is None or g2 != f:
        bad += 1; print(f"MISMATCH roundtrip {name}: cycles={ci}")
    else:
        inv_cycles.add(ci)
    write_poly(f)                       # inverse of the raw polynomial
    ci2, _ = run(b"I")
    g3, _ = read_poly()
    checks += 1
    if ci2 is None or g3 != O.ntt_inv(f):
        bad += 1; print(f"MISMATCH inverse {name}: cycles={ci2}")
print(f"{checks} comparisons over {len(vecs)} polynomials, {bad} mismatches")

# core clock, measured on chip: core clocks counted in 1 ms of the 27 MHz crystal
time.sleep(0.01)
os.write(fd, b"Q"); q = read(4, 1.0)
khz = (q[1] | (q[2] << 8) | (q[3] << 16)) if len(q) == 4 and q[:1] == b"K" else None
print(f"core clock measured on chip: {khz} kHz")

# throughput: n back-to-back forward transforms, total clocks from first start to last done
reps = min(args.reps, 255)
os.write(fd, b"B" + bytes([reps]))
b = read(4, 5.0)
tot = (b[1] | (b[2] << 8) | (b[3] << 16)) if len(b) == 4 and b[:1] == b"K" else None
print(f"{reps} back-to-back forward transforms: {tot} clocks")

res = dict(label=args.label, lanes=lanes, reduction="barrett" if red else "montgomery",
           mismatches=bad, comparisons=checks, polynomials=len(vecs),
           forward_cycles=sorted(fwd_cycles), inverse_cycles=sorted(inv_cycles),
           core_clock_khz=khz, back_to_back_reps=reps, back_to_back_clocks=tot,
           uart_write_s=round(sum(xfer[0::2]) / len(xfer[0::2]), 4),
           uart_read_s=round(sum(xfer[1::2]) / len(xfer[1::2]), 4),
           run_command_wall_s=round(sum(wall) / len(wall), 4), when=time.strftime("%Y-%m-%d %H:%M:%S"))
if khz and fwd_cycles:
    f_hz = khz * 1e3
    res["forward_us"] = round(min(fwd_cycles) / f_hz * 1e6, 3)
    res["inverse_us"] = round(min(inv_cycles) / f_hz * 1e6, 3) if inv_cycles else None
    if tot: res["throughput_forward_per_s"] = round(reps * f_hz / tot)
print(json.dumps(res, indent=1))
if args.out:
    json.dump(res, open(args.out, "w"), indent=1)
sys.exit(1 if bad or not fwd_cycles else 0)
