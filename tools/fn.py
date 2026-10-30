"""fn.py 0xRVA [count]: disassemble the function holding RVA."""
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sys; from sr5img import Img
img = Img(); r = int(sys.argv[1], 16)
f = img.func(r) or (r, r + 0x300)
n = int(sys.argv[2]) if len(sys.argv) > 2 else 400
print(f'; function {f[0]:X}-{f[1]:X}')
print('\n'.join(img.dis(f[0], f[1], n)))
