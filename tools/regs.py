"""regs.py 0xREGFN: list static registrations 'lea r9,fn; lea rdx,"name"; lea rcx,obj; call REGFN'."""
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sr5img import Img
import capstone, re
img = Img(); reg = int(sys.argv[1], 16)
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
for site in img.rip_xrefs(reg):
    st = site - 1
    if img.mem[st] != 0xE8: continue
    f = img.func(st); beg = f[0] if f else st - 0x40
    regs = {}
    for ins in md.disasm(img.mem[beg:st + 5], beg):
        m = re.match(r'(r\w+|e\w+), \[rip ([+-]) 0x([0-9a-f]+)\]', ins.op_str)
        if ins.mnemonic == 'lea' and m:
            regs[m.group(1)] = ins.address + ins.size + int(m.group(3), 16) * (1 if m.group(2) == '+' else -1)
        if ins.address == st: break
    name = img.cstr(regs['rdx']) if 'rdx' in regs else '?'
    print(f'{regs.get("r9", 0):8X}  {name}   (obj {regs.get("rcx", 0):X}, init {beg:X})')
