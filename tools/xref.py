"""xref.py "string" | 0xRVA : who references it (function begin, site)."""
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sys; from sr5img import Img
img = Img()
for arg in sys.argv[1:]:
    if arg.startswith('0x'): targets = [int(arg, 16)]
    else: targets = img.find_str(arg) + [t for t in img.find_str(arg, True)]
    for t in targets:
        print(f'## {arg} @ {t:X}')
        for site in img.rip_xrefs(t):
            f = img.func(site)
            print(f'  site {site:X}  in fn {f[0]:X}' if f else f'  site {site:X}')
        # data pointers (absolute VA)
        import struct
        va = struct.pack('<Q', t + 0x140000000); i = 0
        while (i := img.mem.find(va, i)) >= 0:
            print(f'  dataptr at {i:X}'); i += 8
