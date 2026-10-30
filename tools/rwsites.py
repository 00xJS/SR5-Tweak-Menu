"""rwsites.py 0xRVA: instructions that touch a global (rip-relative), with their functions."""
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sr5img import Img
import capstone
img = Img(); t = int(sys.argv[1], 16)
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
seen = set()
for site in img.rip_xrefs(t, extra=(0, 1, 2, 4)):
    for back in range(1, 12):
        st = site - back
        ins = next(md.disasm(img.mem[st:st + 16], st), None)
        if ins and ins.address + ins.size > site >= st and img.annot(ins).startswith(f'{t:X}') and st not in seen:
            seen.add(st); f = img.func(st)
            print(f'{st:X} fn {f[0] if f else 0:X}: {ins.mnemonic} {ins.op_str}'); break
