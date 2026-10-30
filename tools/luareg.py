"""luareg.py: every {name, C function} pair built as lea-name / lea-fn stores (Lua registration lists)."""
import os, sys, re; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sr5img import Img
import capstone
img = Img()
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
fns = [int(a, 16) for a in sys.argv[1:]]
for f0 in fns:
    import numpy as np
    i = int(np.searchsorted(img.fbeg, f0, 'right')) - 1
    b, e = int(img.fbeg[i]), int(img.fend[i])
    pend = None
    for ins in md.disasm(img.mem[b:e], b):
        m = re.match(r'(\w+), \[rip ([+-]) 0x([0-9a-f]+)\]', ins.op_str)
        if ins.mnemonic == 'lea' and m:
            t = ins.address + ins.size + int(m.group(3), 16) * (1 if m.group(2) == '+' else -1)
            s = img.mem[t:t + 64]; z = s.find(b'\0')
            if z > 2 and all(32 < c < 127 for c in s[:z]): pend = s[:z].decode()
            elif pend and img.secs['.text'][0] <= t < img.secs['.text'][0] + img.secs['.text'][1]:
                print(f'{t:8X}  {pend}'); pend = None
