# Load a cmtz design to SRAM, check all 289 (a,b) pairs against bench's reference vectors,
# then time UART round trips. Usage: python3 -I board.py <project> <nreply> <refcol>
import os, glob, sys, termios, time, select, subprocess
proj, nrep, col = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])   # col: first reference column in "V a b ..." lines
root = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../projects/cmtz', proj))
subprocess.run(['openFPGALoader', '-c', 'ft2232', os.path.join(root, '_build/default/hardware.fs')], check=True, capture_output=True)
ref = {}
for l in subprocess.run([os.path.join(os.path.dirname(__file__), 'bench'), 'v'], capture_output=True, text=True).stdout.splitlines():
    if l.startswith('V '):
        f = list(map(int, l.split()[1:])); ref[(f[0], f[1])] = f[col:col+nrep]
port = glob.glob('/dev/serial/by-id/usb-SIPEED_USB_Debugger_*-if01-port0')[0]
fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
a = termios.tcgetattr(fd); a[0]=a[1]=a[3]=0; a[2]=termios.CS8|termios.CREAD|termios.CLOCAL
a[4]=a[5]=termios.B115200; termios.tcsetattr(fd, termios.TCSANOW, a)
def read(n, t):
    out=b''; end=time.time()+t
    while len(out)<n and time.time()<end:
        if select.select([fd],[],[],0.02)[0]: out+=os.read(fd,64)
    return out
q = time.time()
while time.time()-q < 1.0:
    if read(65536, 0.1): q = time.time()
def ask(x, y):
    os.write(fd, bytes([x, y])); return read(nrep, 0.5)
bad = sum(ask(x, y) != bytes(ref[(x, y)]) for (x, y) in ref)
print(f'{proj}: {len(ref)} pairs, {bad} mismatches vs C++')
N = 1000; t = time.perf_counter()
for i in range(N): ask(i % 17, (i * 5) % 17)
dt = (time.perf_counter() - t) / N
print(f'{proj}: UART round trip {dt*1e3:.2f} ms/op = {1/dt:.0f} op/s')
