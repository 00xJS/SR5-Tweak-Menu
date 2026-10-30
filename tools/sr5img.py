"""Shared loader for SaintsRow.exe analysis: mapped image, pdata, xrefs.
Caches the mapped image as sr5.img next to this script (game data: keep out of git)."""
import os, sys, struct, bisect
import numpy as np
EXE = os.environ.get('SR5_EXE', r'C:\Program Files\Epic Games\SaintsRow\sr5\SaintsRow_DX12.exe')
HERE = os.path.dirname(os.path.abspath(__file__))
BASE = 0x140000000

class Img:
    def __init__(self):
        import pefile
        pe = pefile.PE(EXE, fast_load=True)
        self.size = pe.OPTIONAL_HEADER.SizeOfImage
        cache = os.path.join(HERE, os.path.splitext(os.path.basename(EXE))[0] + '.img')
        if os.path.exists(cache) and os.path.getsize(cache) == self.size and os.path.getmtime(cache) > os.path.getmtime(EXE):
            self.mem = open(cache, 'rb').read()
        else:
            m = bytearray(self.size)
            raw = open(EXE, 'rb').read()
            m[:0x1000] = raw[:0x1000]
            for s in pe.sections:
                d = raw[s.PointerToRawData:s.PointerToRawData + s.SizeOfRawData]
                m[s.VirtualAddress:s.VirtualAddress + len(d)] = d
            self.mem = bytes(m)
            open(cache, 'wb').write(self.mem)
        self.secs = {s.Name.rstrip(b'\0').decode(): (s.VirtualAddress, s.Misc_VirtualSize) for s in pe.sections}
        pd, pn = self.secs['.pdata']
        a = np.frombuffer(self.mem[pd:pd + pn - pn % 12], dtype='<u4').reshape(-1, 3)
        self.fbeg = a[:, 0].copy(); self.fend = a[:, 1].copy(); self.funw = a[:, 2].copy()

    def u32(self, r): return struct.unpack_from('<I', self.mem, r)[0]
    def u64(self, r): return struct.unpack_from('<Q', self.mem, r)[0]
    def cstr(self, r, n=200):
        e = self.mem.find(b'\0', r, r + n); return self.mem[r:e].decode('latin1')

    def func(self, rva):
        """(begin, end) of the pdata entry holding rva, following chained unwind to the primary."""
        i = int(np.searchsorted(self.fbeg, rva, 'right')) - 1
        if i < 0 or rva >= self.fend[i]: return None
        b, e, u = int(self.fbeg[i]), int(self.fend[i]), int(self.funw[i])
        for _ in range(8):  # chained unwind info: primary function's begin
            if u & 1: break
            flags = self.mem[u] >> 3
            if not flags & 4: break
            cnt = self.mem[u + 2]; off = u + 4 + ((cnt + 1) & ~1) * 2
            b2 = self.u32(off)
            if b2 == b: break
            b = b2
        return b, e

    def find_str(self, s, wide=False):
        enc = s.encode('utf-16le') if wide else s.encode()
        out, i = [], 0
        while True:
            i = self.mem.find(b'\0' + enc + (b'\0\0' if wide else b'\0'), i)
            if i < 0: return out
            out.append(i + 1); i += 1

    _disp = None
    def rip_xrefs(self, target, extra=(0, 1, 4)):
        """Text offsets whose rel32 (RIP-relative disp or call/jmp rel) points at target."""
        tb, tn = self.secs['.text']
        if Img._disp is None:
            t = np.frombuffer(self.mem[tb:tb + tn], dtype=np.uint8)
            n = len(t) - 4
            d = (t[0:n].astype(np.int64) | (t[1:n+1].astype(np.int64) << 8) | (t[2:n+2].astype(np.int64) << 16) | (t[3:n+3].astype(np.int64) << 24))
            d = np.where(d >= 1 << 31, d - (1 << 32), d)
            Img._disp = d + np.arange(n, dtype=np.int64) + tb + 4
        res = []
        for x in extra:
            res += [int(i) + tb for i in np.nonzero(Img._disp + x == target)[0]]
        return sorted(set(res))

    def dis(self, beg, end=None, maxn=4000):
        import capstone
        if end is None:
            f = self.func(beg); end = f[1] if f else beg + 0x200
        md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
        out = []
        for ins in md.disasm(self.mem[beg:end], beg):
            line = f'{ins.address:08X}  {ins.mnemonic:7} {ins.op_str}'
            note = self.annot(ins)
            out.append(line + (f'    ; {note}' if note else ''))
            if len(out) >= maxn: break
        return out

    def annot(self, ins):
        import re
        m = re.search(r'\[rip ([+-]) 0x([0-9a-f]+)\]', ins.op_str)
        t = None
        if m:
            t = ins.address + ins.size + (int(m.group(2), 16) * (1 if m.group(1) == '+' else -1))
        elif ins.mnemonic in ('call', 'jmp', 'lea') and re.fullmatch(r'0x[0-9a-f]+', ins.op_str):
            t = int(ins.op_str, 16)
        if t is None or not (0 < t < self.size): return ''
        s = self.mem[t:t + 80]
        e = s.find(b'\0')
        if e >= 4 and all(32 <= c < 127 for c in s[:e]): return f'{t:X} "{s[:e].decode()}"'
        if len(s) > 8 and s[1] == 0 and s[3] == 0 and 32 <= s[0] < 127 and 32 <= s[2] < 127:
            w = self.mem[t:t + 160].decode('utf-16le', 'ignore').split('\0')[0]
            return f'{t:X} L"{w}"'
        return f'{t:X}'
