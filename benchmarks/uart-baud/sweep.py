# Rebuild cmtz-mul at several baud rates, load to SRAM, check all 289 pairs and time round trips.
# Usage: source ../../env.sh && python3 -I sweep.py 115200 921600 ...
import os, glob, sys, termios, time, select, subprocess, re
here = os.path.dirname(os.path.abspath(__file__))
def run(cmd): return subprocess.run(cmd, cwd=here, capture_output=True, text=True)
for baud in map(int, sys.argv[1:]):
    cpb = round(27_000_000 / baud)
    src = open(f'{here}/cmtz_mul_uart.v').read()
    src = re.sub(r'(module cmtz_mul_uart #\(\s*parameter CLKS_PER_BIT = )\d+', rf'\g<1>{cpb}', src)
    open(f'{here}/cmtz_mul_uart.v', 'w').write(src)
    b = run(['apio', 'build']); assert 'SUCCESS' in b.stdout + b.stderr, b.stdout[-500:]
    run(['openFPGALoader', '-c', 'ft2232', '_build/default/hardware.fs'])
    port = glob.glob('/dev/serial/by-id/usb-SIPEED_USB_Debugger_*-if01-port0')[0]
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    a = termios.tcgetattr(fd); a[0]=a[1]=a[3]=0; a[2]=termios.CS8|termios.CREAD|termios.CLOCAL
    a[4]=a[5]=getattr(termios, f'B{baud}'); termios.tcsetattr(fd, termios.TCSANOW, a)
    def read(n, t):
        out=b''; end=time.time()+t
        while len(out)<n and time.time()<end:
            if select.select([fd],[],[],0.02)[0]: out+=os.read(fd,64)
        return out
    q = time.time()
    while time.time()-q < 1.0:
        if read(65536, 0.1): q = time.time()
    def ask(x, y): os.write(fd, bytes([x, y])); return read(1, 0.5)
    bad = sum(ask(x, y) != bytes([x*y % 17]) for x in range(17) for y in range(17))
    N = 500; t = time.perf_counter()
    for i in range(N): ask(i % 17, (i*5) % 17)
    dt = (time.perf_counter()-t)/N
    err = (27e6/cpb - baud)/baud*100
    print(f'{baud:8d} baud (CLKS_PER_BIT {cpb}, {err:+.1f}% err): {bad} mismatches/289, {dt*1e3:.2f} ms/op', flush=True)
    os.close(fd)
