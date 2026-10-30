"""vtbl.py CLASSNAME [n]: MSVC RTTI -> vtable RVA(s) and first n virtual functions."""
import sys, struct
sys.path.insert(0, r'C:/Users/Joseph/dev/SR5-Tweaks/tools')
from sr5img import Img, BASE
img = Img()
name = sys.argv[1]; n = int(sys.argv[2]) if len(sys.argv) > 2 else 12
mem = img.mem
for tag in (b'.?AU', b'.?AV'):
    s = tag + name.encode() + b'@@\0'
    i = mem.find(s)
    if i < 0: continue
    td = i - 0x10
    print(f'type descriptor {td:X} ({s[:-1].decode()})')
    pat = struct.pack('<I', td)
    j = 0
    while (j := mem.find(pat, j)) >= 0:
        col = j - 0xC
        if col % 4 == 0 and struct.unpack_from('<I', mem, col)[0] == 1:
            va = struct.pack('<Q', col + BASE); k = 0
            while (k := mem.find(va, k)) >= 0:
                vt = k + 8
                fns = [struct.unpack_from('<Q', mem, vt + 8 * x)[0] - BASE for x in range(n)]
                print(f'  COL {col:X} offset {struct.unpack_from("<I", mem, col + 4)[0]:X} vtable {vt:X}:', ' '.join(f'{f:X}' for f in fns))
                k += 8
        j += 4
