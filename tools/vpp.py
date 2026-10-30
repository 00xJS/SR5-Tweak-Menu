"""vpp.py ARCHIVE OUTDIR [regex]: list/extract entries (recursing into nested packfiles) whose name matches regex."""
import sys, struct, re, os
def lz4_block(src, out):
    i = 0; n = len(src)
    while i < n:
        tok = src[i]; i += 1
        l = tok >> 4
        if l == 15:
            while True:
                b = src[i]; i += 1; l += b
                if b != 255: break
        out += src[i:i+l]; i += l
        if i >= n: break
        off = src[i] | (src[i+1] << 8); i += 2
        ml = tok & 15
        if ml == 15:
            while True:
                b = src[i]; i += 1; ml += b
                if b != 255: break
        ml += 4
        s = len(out) - off
        if off >= ml: out += out[s:s+ml]
        else:
            for k in range(ml): out.append(out[s+k])
    return out
def lz4_frame(d):
    out = bytearray(); p = 0
    while p + 4 <= len(d) and d[p:p+4] == b'\x04\x22\x4d\x18':
        flg = d[p+4]; p += 6
        if flg & 8: p += 8
        if flg & 1: p += 4
        p += 1
        while True:
            bs = struct.unpack_from('<I', d, p)[0]; p += 4
            if bs == 0: break
            sz = bs & 0x7FFFFFFF
            blk = d[p:p+sz]; p += sz
            if bs & 0x80000000: out += blk
            else: lz4_block(blk, out)
            if flg & 0x10: p += 4
        if flg & 4: p += 4
    return bytes(out)
def parse(get, base, depth, pat, outdir, prefix=''):
    h = get(base, 0x78)
    if h[:4] != b'\xce\x0a\x89\x51': return
    nfiles, npaths, namesz = struct.unpack_from('<III', h, 0x10)
    flags = struct.unpack_from('<I', h, 0xC)[0]
    dataoff = struct.unpack_from('<Q', h, 0x40)[0]
    ents = get(base + 0x78, nfiles * 0x30)
    names = get(base + 0x78 + nfiles * 0x30 + npaths * 8, namesz)
    def nm(o):
        e = names.find(b'\0', o); return names[o:e].decode('latin1')
    for k in range(nfiles):
        no, po, do, sz, csz, fl = struct.unpack_from('<QQQQqI', ents, k * 0x30)
        name = nm(no)
        stored = sz if csz < 0 else csz
        full = prefix + name
        if name.endswith(('.str2_pc', '.vpp_pc')) and depth < 3 and (depth > 0 or 'vintdoc' in name):
            if csz < 0:
                parse(get, base + dataoff + do, depth + 1, pat, outdir, full + '/')
            else:
                raw = lz4_frame(get(base + dataoff + do, stored))
                parse(lambda o, n: raw[o:o+n], 0, depth + 1, pat, outdir, full + '/')
        elif pat.search(name):
            raw = get(base + dataoff + do, stored)
            if csz >= 0:
                try: raw = lz4_frame(raw)
                except Exception as ex: print('fail', full, ex); continue
            fn = os.path.join(outdir, name)
            open(fn, 'wb').write(raw)
            print(full, len(raw))
f = open(sys.argv[1], 'rb')
def get(o, n): f.seek(o); return f.read(n)
os.makedirs(sys.argv[2], exist_ok=True)
parse(get, 0, 0, re.compile(sys.argv[3] if len(sys.argv) > 3 else r'\.lua$'), sys.argv[2])
