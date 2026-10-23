#!/usr/bin/env python3
"""Diagnostic board test for the 'swap' lane build: checks the memory / crossbar / control
path alone. Expected data comes from the Python cycle model, not from an NTT."""
import glob, importlib.util, os, select, sys, termios, time, random
CM = os.path.expanduser(os.environ.get("CMTZ_REPO", "~/code/cook_mertz"))
sys.path.insert(0, CM)
from cmtz.accel.mlkem_ntt.config import NTTConfig
from cmtz.accel.mlkem_ntt import sched, words, model
lanes = int(sys.argv[1]) if len(sys.argv) > 1 else 4
cfg = NTTConfig(lanes=lanes, lane="swap")
def expect(f, inv):
    s = sched.schedule(cfg, inv); m = model.Machine(cfg, s.bank_map); m.load(f)
    m.run(words.build_words(s), inv); return m.dump()
fd = os.open(glob.glob('/dev/serial/by-id/usb-SIPEED_USB_Debugger_*-if01-port0')[0], os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
a = termios.tcgetattr(fd); a[0]=a[1]=a[3]=0; a[2]=termios.CS8|termios.CREAD|termios.CLOCAL; a[4]=a[5]=termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, a)
def rd(n, t):
    o=b''; e=time.time()+t
    while len(o) < n and time.time() < e:
        if select.select([fd],[],[],.02)[0]: o += os.read(fd, 4096)
    return o
rd(65536, 1.0)
def wr(f):
    b = bytearray(b'W')
    for c in f: b += bytes([c & 255, c >> 8])
    os.write(fd, bytes(b)); return rd(1, 2)
def rp():
    os.write(fd, b'R'); d = rd(512, 2)
    return [d[2*i] | d[2*i+1] << 8 for i in range(256)] if len(d) == 512 else None
rng = random.Random(5); bad = 0; n = 0
for t in range(8):
    f = [rng.randrange(3329) for _ in range(256)]
    for inv in (0, 1):
        wr(f); os.write(fd, b'I' if inv else b'F'); r = rd(3, 2)
        g = rp(); e = expect(f, bool(inv)); n += 1
        if g != e:
            bad += 1; diff = [i for i in range(256) if g is None or g[i] != e[i]]
            print("MISMATCH", "inv" if inv else "fwd", "nbad", len(diff), diff[:8])
print(f"swap-lane check: {n} transforms, {bad} mismatching")
sys.exit(1 if bad else 0)
