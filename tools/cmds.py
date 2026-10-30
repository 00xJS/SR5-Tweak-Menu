import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from live import Live
L = Live(); print('pid', L.pid, 'base %X' % L.base)
print('console ready byte 5BEB094 =', L.u8(0x5BEB094), ' verbose 5BEA940 =', L.u32(0x5BEA940))
n = L.u32(0x5BEB05C); print('commands:', n)
for i in range(n):
    c = L.q(L.base + 0x4BA9E50 + i * 8)
    raw = L.read(c, 0x28)
    name = L.cstr(L.q(c)); fn = L.q(c + 0x10); hlp = L.q(c + 0x18); typ, dis = raw[0x20], raw[0x24]
    print(f'{name:48} type={typ} disabled={dis} fn={fn - L.base if fn else 0:X} {L.cstr(hlp) if hlp else ""}')
