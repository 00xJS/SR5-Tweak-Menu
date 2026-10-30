"""rcls.py CLASS [CLASS...]: field layout of a reflection class (byte offset, size, name, last strings = display name/default)."""
import sys, re, struct
d = open(r'C:/Program Files/Epic Games/SaintsRow/sr5/data/reflection/reflection.vpp_pc', 'rb').read()
recre = re.compile(rb'\x01(....)(..)(m_[A-Za-z0-9_]+|operator=|!!!|~~~)', re.S)

def find(cname):
    key = struct.pack('<H', len(cname)) + cname.encode()
    hits = []; pos = 0
    while (p := d.find(key, pos)) >= 0:
        nx = d[p + len(key)]
        if not (48 <= nx < 58 or 65 <= nx < 91 or 97 <= nx < 123 or nx in (95, 58, 60)): hits.append(p)
        pos = p + 1
    cands = []
    for p in hits:
        end = d.find(b'operator=', p)
        rs = [m for m in recre.finditer(d, p, end + 16) if struct.unpack('<H', m.group(2))[0] == len(m.group(3))]
        if any(m.group(3).startswith(b'm_') for m in rs): cands.append((p, end, rs))
    return cands

def dump(cname, which=0):
    cands = find(cname)
    if not cands: print('no', cname); return
    p, end, rs = cands[min(which, len(cands) - 1)]
    print(f'== {cname} @{p:X} ({len(cands)} copies)')
    for i, m in enumerate(rs):
        s = m.group(3).decode()
        if not s.startswith('m_'): continue
        nxt = rs[i + 1].start() if i + 1 < len(rs) else end - 7
        bo, bs = struct.unpack_from('<II', d, nxt - 8)
        body = d[m.end():nxt - 8]
        strs = [x.group().decode() for x in re.finditer(rb'[\x20-\x7e]{3,}', body)]
        dflt = ' / '.join(strs[-2:])
        sz = bs // 8 if bs % 8 == 0 else f'{bs}b'
        print(f'  +0x{bo // 8:04X} {sz!s:>5} {s:48} {dflt[:70]}')

if __name__ == '__main__':
    for c in sys.argv[1:]: dump(c)
