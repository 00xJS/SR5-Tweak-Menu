"""scan.py HEXBYTES [max]: find a byte pattern in the running game's committed read-write memory (read-only scan)."""
import os, sys, ctypes, ctypes.wintypes as W
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from live import Live, k32
class MBI(ctypes.Structure):
    _fields_ = [('BaseAddress', ctypes.c_void_p), ('AllocationBase', ctypes.c_void_p), ('AllocationProtect', W.DWORD), ('PartitionId', W.WORD),
                ('RegionSize', ctypes.c_size_t), ('State', W.DWORD), ('Protect', W.DWORD), ('Type', W.DWORD)]
L = Live(); pat = bytes.fromhex(sys.argv[1]); maxhits = int(sys.argv[2]) if len(sys.argv) > 2 else 20
addr, hits, mbi = 0, [], MBI()
while addr < 0x7FFFFFFFFFFF and len(hits) < maxhits:
    if not k32.VirtualQueryEx(L.h, ctypes.c_void_p(addr), ctypes.byref(mbi), ctypes.sizeof(mbi)): break
    base, size = mbi.BaseAddress or 0, mbi.RegionSize
    if mbi.State == 0x1000 and mbi.Protect in (0x04, 0x08, 0x40) and size < (1 << 31):
        off = 0
        while off < size:
            n = min(1 << 24, size - off)
            d = L.read(base + off, n + len(pat))
            if d:
                i = d.find(pat)
                while i >= 0 and len(hits) < maxhits:
                    hits.append(base + off + i); i = d.find(pat, i + 1)
            off += n
    addr = base + size
for h in hits:
    rel = h - L.base
    print(hex(h), f'(exe+{rel:X})' if 0 <= rel < 0x6000000 else '')
