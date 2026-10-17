# Exercise the cmtz-mul board design over the UART; compares every reply to (a*b) % 17.
import os, glob, sys, termios, time, select
port = glob.glob('/dev/serial/by-id/usb-SIPEED_USB_Debugger_*-if01-port0')[0]
fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
a = termios.tcgetattr(fd); a[0]=a[1]=a[3]=0; a[2]=termios.CS8|termios.CREAD|termios.CLOCAL
a[4]=a[5]=termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, a)
def read(n, t):
    out=b''; end=time.time()+t
    while len(out)<n and time.time()<end:
        if select.select([fd],[],[],0.02)[0]: out+=os.read(fd,64)
    return out
def ask(x, y):
    os.write(fd, bytes([x, y]))
    return read(1, 0.5)
# drain stale bytes (the debugger buffers old output) until the port is quiet for 1 s
total = 0; quiet_since = time.time()
while time.time() - quiet_since < 1.0:
    chunk = read(65536, 0.1)
    if chunk: total += len(chunk); quiet_since = time.time()
print(f'drained {total} stale bytes')
tests = [(3,5),(16,16),(0,0),(1,1),(17,1),(1,17),(255,0),(0,255)]
if len(sys.argv) > 1 and sys.argv[1] == 'all':
    tests = [(x,y) for x in range(17) for y in range(17)] + [(17,1),(1,17),(255,0),(0,255),(200,200)]
bad = 0
for x, y in tests:
    exp = 0xFF if (x >= 17 or y >= 17) else (x*y) % 17
    got = ask(x, y)
    ok = got == bytes([exp])
    bad += not ok
    if not ok or len(tests) <= 10:
        print(f'{x:3d} {y:3d} -> got {got.hex() or "none"} expected {exp:02x} {"ok" if ok else "MISMATCH"}')
print(f'{len(tests)} pairs, {bad} mismatches')
