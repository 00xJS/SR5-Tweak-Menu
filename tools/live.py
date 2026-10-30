"""Read the running SaintsRow_DX12.exe (read-only). live.py is a module: L = Live(); L.u8(rva)..."""
import ctypes, ctypes.wintypes as W, struct, sys, os
k32 = ctypes.WinDLL('kernel32', use_last_error=True)
psapi = ctypes.WinDLL('psapi')
class Live:
    def __init__(self, name=os.environ.get('SR5_PROC', 'SaintsRow_DX12.exe')):
        import subprocess
        out = subprocess.run(['tasklist', '/FI', f'IMAGENAME eq {name}', '/FO', 'CSV', '/NH'], capture_output=True, text=True).stdout
        self.pid = int(out.split('","')[1])
        self.h = k32.OpenProcess(0x0410, False, self.pid)  # QUERY_INFORMATION | VM_READ
        mods = (W.HMODULE * 1024)(); need = W.DWORD()
        psapi.EnumProcessModulesEx(self.h, mods, ctypes.sizeof(mods), ctypes.byref(need), 3)
        self.base = mods[0]
    def read(self, addr, n):
        b = ctypes.create_string_buffer(n); got = ctypes.c_size_t()
        if not k32.ReadProcessMemory(self.h, ctypes.c_void_p(addr), b, n, ctypes.byref(got)): return None
        return b.raw[:got.value]
    def r(self, rva, n): return self.read(self.base + rva, n)
    def u8(self, rva): return self.r(rva, 1)[0]
    def u32(self, rva): return struct.unpack('<I', self.r(rva, 4))[0]
    def q(self, addr): d = self.read(addr, 8); return struct.unpack('<Q', d)[0] if d else None
    def cstr(self, addr, n=128):
        d = self.read(addr, n) or b''; return d.split(b'\0')[0].decode('latin1')
