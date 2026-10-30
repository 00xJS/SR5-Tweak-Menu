"""stack.py TID [samples]: sample a thread of the running game; print exe return addresses (outermost last)."""
import os, sys, ctypes, ctypes.wintypes as W, struct, collections, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from live import Live
from sr5img import Img
k32 = ctypes.WinDLL('kernel32', use_last_error=True)
L = Live(); img = Img()
tid = int(sys.argv[1]); samples = int(sys.argv[2]) if len(sys.argv) > 2 else 20
class CONTEXT(ctypes.Structure):
    _align_ = 16
    _fields_ = [('P', ctypes.c_uint64 * 6), ('ContextFlags', W.DWORD), ('MxCsr', W.DWORD), ('Seg', W.WORD * 6), ('EFlags', W.DWORD),
                ('Dr', ctypes.c_uint64 * 6), ('Rax', ctypes.c_uint64), ('Rcx', ctypes.c_uint64), ('Rdx', ctypes.c_uint64), ('Rbx', ctypes.c_uint64),
                ('Rsp', ctypes.c_uint64), ('Rbp', ctypes.c_uint64), ('Rsi', ctypes.c_uint64), ('Rdi', ctypes.c_uint64), ('R', ctypes.c_uint64 * 8),
                ('Rip', ctypes.c_uint64), ('rest', ctypes.c_byte * 1232)]
h = k32.OpenThread(0x0002 | 0x0008, False, tid)  # SUSPEND_RESUME | GET_CONTEXT
assert h, ctypes.get_last_error()
ctx_buf = ctypes.create_string_buffer(ctypes.sizeof(CONTEXT) + 16)
addr = (ctypes.addressof(ctx_buf) + 15) & ~15
ctx = CONTEXT.from_address(addr)
tb, tn = img.secs['.text']
def is_ret(r):
    # a return address: inside .text and preceded by a call instruction
    if not (tb <= r < tb + tn): return False
    m = img.mem
    return m[r - 5] == 0xE8 or (m[r - 6] == 0xFF and m[r - 5] == 0x15) or (m[r - 2] == 0xFF and (m[r - 1] & 0x38) == 0x10) or (m[r - 3] == 0xFF and (m[r - 2] & 0x38) == 0x10)
counts = collections.Counter(); chains = []
for s in range(samples):
    k32.SuspendThread(h)
    ctx.ContextFlags = 0x100003
    k32.GetThreadContext(h, ctypes.c_void_p(addr))
    rsp, rip = ctx.Rsp, ctx.Rip
    data = L.read(rsp, 0x20000) or L.read(rsp, 0x8000) or b''
    k32.ResumeThread(h)
    chain = []
    for i in range(0, len(data) - 8, 8):
        v = struct.unpack_from('<Q', data, i)[0] - L.base
        if 0 < v < img.size and is_ret(v): chain.append(v)
    chains.append(chain); counts.update(set(chain))
    time.sleep(0.05)
print('rip sample', hex(rip - L.base) if L.base <= rip < L.base + img.size else hex(rip))
common = [r for r, c in counts.items() if c == samples]
print('in every sample (outermost last):')
for r in chains[-1]:
    if r in common:
        f = img.func(r - 1); print(f'  ret {r:X}  in fn {f[0]:X}' if f else f'  ret {r:X}')
