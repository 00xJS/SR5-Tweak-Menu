"""srtex.py: Saints Row (2022) textures, .cvbm_pc header + .gvbm_pc low mips + .gvbh_pc high mips, to PNG and back.
Only reads the game's files; writes only where OUTDIR says. Needs numpy. Not tested in the game.
  python -I tools/srtex.py list ARCHIVE [REGEX] [--entry STR2]
  python -I tools/srtex.py export SOURCE TEXTURE OUTDIR [--mips]
  python -I tools/srtex.py import SIDECAR.json IN.png OUTDIR [--no-reuse] [--onto EARLIER.str2_pc]
  python -I tools/srtex.py strh IN.strh_pc OUT.strh_pc IMPORT_REPORT.json
SOURCE is a .vpp_pc, a .str2_pc file, or a .cvbm_pc with its .gvbm_pc/.gvbh_pc beside it. TEXTURE is `x.cvbm_pc.str2_pc`, or
`prefab.cprefab_pc.str2_pc:x` for one inside a prefab archive; use - for a file SOURCE holding one texture.
Import keeps the file's format, sizes and mip count, and reuses the original bytes of every block the PNG didn't change, so an
untouched PNG gives back identical files. Editing two textures of one archive: pass the first result as --onto for the second. Encoders: BC1, BC4, BC5, BC7 (modes 1, 3, 5, 6, 7), RGBA8, 16-bit LUTs. BC6H and
16-bit float export for viewing only: import refuses them unless unchanged."""
import base64, glob, hashlib, json, os, re, struct, sys, zlib
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import packbuild as pb

# ---- header. Names and numbers of formats: the game's BM_FORMAT_PC table, exe file offset 0x2E7F318
FORMATS = {0x190: ('BC1', 8), 0x191: ('BC2', 16), 0x192: ('BC3', 16), 0x193: ('565', -2), 0x194: ('1555', -2), 0x195: ('4444', -2),
           0x196: ('888', -3), 0x197: ('8888', -4), 0x198: ('16_DUDV', -2), 0x199: ('16_DOT3', -2), 0x19A: ('R8', -1), 0x19B: ('BC6HU', 16),
           0x19C: ('BC6HS', 16), 0x19D: ('BC7', 16), 0x19E: ('BC4', 8), 0x19F: ('BC5', 16), 0x1A0: ('16161616', -8), 0x1A1: ('32323232', -16),
           0x1A2: ('16161616_UNORM', -8)}
F_HAS_HIGH, F_LINEAR, F_SLICES = 0x08, 0x02, 0x01    # byte +0x37
F36_ALPHA, F36_CUBE = 0x01, 0x08                     # byte +0x36

def parse_cvbm(b):
    if b[:4] != b'GEKV' or struct.unpack_from('<I', b, 4)[0] != 19: raise SystemExit('not a version 19 GEKV header')
    h = {'gsize': struct.unpack_from('<I', b, 0xC)[0], 'hsize': struct.unpack_from('<I', b, 0x18)[0]}
    h['hw'], h['hh'] = struct.unpack_from('<HH', b, 0x1C)
    h['w'], h['h'], h['fmt'] = struct.unpack_from('<HHH', b, 0x28)
    h['cols'], h['rows'] = [max(1, x) for x in struct.unpack_from('<HH', b, 0x30)]
    h['f36'], h['f37'] = b[0x36], b[0x37]
    h['avg'] = struct.unpack_from('<4f', b, 0x38)
    h['gmips'] = b[0x53]; h['hmips'] = struct.unpack_from('<I', b, 0x78)[0]
    h['name'] = b[0x88:].split(b'\0')[0].decode('latin1')
    h['fname'], h['bpb'] = FORMATS.get(h['fmt'], ('?%X' % h['fmt'], 0))
    return h

def surf_size(bpb, w, h):
    return bpb * max(1, (w + 3) // 4) * max(1, (h + 3) // 4) if bpb > 0 else -bpb * w * h

def subresources(h):
    """(store, mip index across both files, slice, offset, size, w, h) in file order. Each file: slice by slice, largest mip first within a slice."""
    out = []; n = h['cols'] * h['rows']; first = 0
    for store, w0, h0, count in (('h', h['hw'], h['hh'], h['hmips']), ('g', h['w'], h['h'], h['gmips'])):
        off = 0
        for s in range(n):
            for i in range(count):
                w, hh = max(1, w0 >> i), max(1, h0 >> i); sz = surf_size(h['bpb'], w, hh)
                out.append((store, first + i, s, off, sz, w, hh)); off += sz
        first += count
    return out

def check_sizes(h):
    t = {'h': 0, 'g': 0}
    for r in subresources(h): t[r[0]] += r[4]
    return t['g'] == h['gsize'] and t['h'] == h['hsize']

# ---- archives
def toc(f, base=0):
    f.seek(base); hd = f.read(0x78)
    if hd[:4] != pb.MAGIC: raise SystemExit('not a packfile')
    nf, np_ = struct.unpack_from('<II', hd, 0x10); do = struct.unpack_from('<Q', hd, 0x40)[0]
    b = f.read(do - 0x78); names = b[nf * 0x30 + np_ * 8:]; out = []
    for k in range(nf):
        no, po, off, sz, csz, fl = struct.unpack_from('<QQQQqI', b, k * 0x30)
        out.append({'name': names[no:names.find(b'\0', no)].decode('latin1'), 'dir': names[po:names.find(b'\0', po)].decode('latin1'),
                    'off': base + do + off, 'raw': sz, 'csz': csz})
    return out

def lz4_unframe(d):
    """As packbuild's, with a quick path for matches that don't overlap: gvbh files reach 10 MB."""
    out = bytearray(); p = 7
    while True:
        bs = struct.unpack_from('<I', d, p)[0]; p += 4
        if bs == 0: return bytes(out)
        sz = bs & 0x7FFFFFFF; blk = d[p:p + sz]; p += sz
        if bs & 0x80000000: out += blk; continue
        i = 0; n = len(blk)
        while i < n:
            t = blk[i]; i += 1; l = t >> 4
            if l == 15:
                while True:
                    b = blk[i]; i += 1; l += b
                    if b != 255: break
            out += blk[i:i + l]; i += l
            if i >= n: break
            off = blk[i] | blk[i + 1] << 8; i += 2; ml = t & 15
            if ml == 15:
                while True:
                    b = blk[i]; i += 1; ml += b
                    if b != 255: break
            ml += 4; s = len(out) - off
            if off >= ml: out += out[s:s + ml]
            else:
                for k in range(ml): out.append(out[s + k])

def stored_of(f, e):
    f.seek(e['off']); return f.read(e['raw'] if e['csz'] < 0 else e['csz'])

def data_root(path):
    parts = os.path.abspath(path).split(os.sep)
    for i in range(len(parts) - 1, -1, -1):
        if parts[i].lower() == 'data': return os.sep.join(parts[:i + 1])

def base_packs(root):
    return [p for p in sorted(glob.glob(os.path.join(root, '*', '*.vpp_pc'))) if not p.endswith('_patch.vpp_pc')]

def find_top(root, d, name):
    """A top-level entry (a gvbh) by its dir and name. The dir names the pack, so try that pack first."""
    m = re.match(r'data\\([^\\]+)', d)
    packs = base_packs(root); first = [p for p in packs if m and os.path.basename(os.path.dirname(p)).lower() == m.group(1).lower()]
    for p in first + [p for p in packs if p not in first]:
        with open(p, 'rb') as f:
            for e in toc(f):
                if e['name'].lower() == name.lower() and e['dir'].lower() == d.lower(): return p, e
    return None, None

class Tex:
    """One texture: raw files, and how they were stored so an unchanged file can keep its exact stored bytes."""
    def __init__(s): s.host = None; s.host_entry = None; s.gvbh = None; s.gvbh_stored = None; s.gvbh_from = None

def get_entry_bytes(st, cs): return lz4_unframe(st) if cs >= 0 else st

def open_tex(source, texture):
    t = Tex(); t.source = source; t.texture = texture
    low = source.lower()
    if low.endswith('.cvbm_pc'):
        t.inner = os.path.basename(source)
        t.cvbm = open(source, 'rb').read(); t.gvbm = open(source[:-8] + '.gvbm_pc', 'rb').read(); t.dir = ''
        if os.path.exists(source[:-8] + '.gvbh_pc'): t.gvbh = open(source[:-8] + '.gvbh_pc', 'rb').read()
        return t
    if low.endswith('.vpp_pc'):
        entry, _, inner = texture.partition(':')
        with open(source, 'rb') as f:
            T = [e for e in toc(f) if e['name'].lower() == entry.lower()]
            if not T: raise SystemExit('no %s in %s' % (entry, source))
            t.host_entry = T[0]; host = stored_of(f, T[0])
            t.host = lz4_unframe(host) if T[0]['csz'] >= 0 else host
    else:
        inner = texture.partition(':')[2] or ('' if texture == '-' else texture)
        t.host = open(source, 'rb').read(); t.host_entry = {'name': os.path.basename(source), 'dir': ''}
    rows = pb.read_pack(t.host); cv = [r for r in rows if r[0].endswith('.cvbm_pc')]
    if inner: cv = [r for r in cv if r[0][:-8].lower() == inner.lower().replace('.cvbm_pc', '').replace('.str2_pc', '')]
    elif len(cv) > 1: cv = [r for r in cv if r[0].lower() + '.str2_pc' == t.host_entry['name'].lower()] or cv
    if len(cv) != 1: raise SystemExit('%d textures match in %s: %s' % (len(cv), t.host_entry['name'], [r[0] for r in cv][:20]))
    t.inner = cv[0][0]; t.dir = cv[0][1]; t.cvbm = get_entry_bytes(cv[0][2], cv[0][4])
    g = [r for r in rows if r[0].lower() == t.inner[:-8].lower() + '.gvbm_pc']
    if not g: raise SystemExit('no gvbm for %s in this archive (a %s has its pixels elsewhere)' % (t.inner, t.host_entry['name']))
    t.gvbm = get_entry_bytes(g[0][2], g[0][4])
    if parse_cvbm(t.cvbm)['hsize']:
        root = data_root(source)
        if root:
            p, e = find_top(root, t.dir, t.inner[:-8] + '.gvbh_pc')
            if e:
                with open(p, 'rb') as f: t.gvbh_stored = stored_of(f, e)
                t.gvbh = get_entry_bytes(t.gvbh_stored, e['csz']); t.gvbh_from = p
    return t

# ---- PNG
def png_write(path, a):
    """a: H x W (grey) or H x W x 3/4, uint8 or uint16."""
    if a.ndim == 2: a = a[:, :, None]
    c = a.shape[2]; ct = {1: 0, 2: 4, 3: 2, 4: 6}[c]; depth = 16 if a.dtype == np.uint16 else 8
    raw = a.astype('>u2').tobytes() if depth == 16 else a.tobytes()
    row = a.shape[1] * c * depth // 8; arr = np.frombuffer(raw, 'u1').reshape(-1, row)
    up = arr.copy(); up[1:] = arr[1:] - arr[:-1]
    body = np.concatenate([np.full((arr.shape[0], 1), 2, 'u1'), up], 1)
    chunk = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', a.shape[1], a.shape[0], depth, ct, 0, 0, 0)))
        f.write(chunk(b'IDAT', zlib.compress(body.tobytes(), 6)) + chunk(b'IEND', b''))

def png_read(path):
    """H x W x C uint8 or uint16, C from 1 to 4. Every colour type at 8 and 16 bits, and palettes; not interlaced."""
    d = open(path, 'rb').read()
    if d[:8] != b'\x89PNG\r\n\x1a\n': raise SystemExit('%s is not a PNG' % path)
    p = 8; idat = []; plte = trns = None
    while p < len(d):
        n = struct.unpack_from('>I', d, p)[0]; t = d[p + 4:p + 8]; c = d[p + 8:p + 8 + n]; p += 12 + n
        if t == b'IHDR': w, h, depth, ct, _, _, il = struct.unpack('>IIBBBBB', c)
        elif t == b'IDAT': idat.append(c)
        elif t == b'PLTE': plte = np.frombuffer(c, 'u1').reshape(-1, 3)
        elif t == b'tRNS': trns = c
    if il: raise SystemExit('interlaced PNG: save it without interlacing')
    if depth not in (8, 16) and ct != 3: raise SystemExit('PNG at %d bits per channel: use 8 or 16' % depth)
    ch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]; bpp = max(1, ch * depth // 8); rowb = (w * ch * depth + 7) // 8
    raw = np.frombuffer(zlib.decompress(b''.join(idat)), 'u1').reshape(h, rowb + 1)
    out = np.zeros((h, rowb), 'u1'); prev = np.zeros(rowb, 'u1')
    for y in range(h):
        ft = raw[y, 0]; r = raw[y, 1:]
        if ft == 0: cur = r.copy()
        elif ft == 2: cur = r + prev
        elif ft == 1:
            cur = r.copy()
            for k in range(bpp): cur[k::bpp] = np.cumsum(r[k::bpp], dtype='u1')
        else:
            cur = bytearray(r.tobytes()); pv = prev.tobytes()
            if ft == 3:
                for i in range(rowb):
                    a = cur[i - bpp] if i >= bpp else 0
                    cur[i] = (cur[i] + ((a + pv[i]) >> 1)) & 255
            else:
                for i in range(rowb):
                    a = cur[i - bpp] if i >= bpp else 0; b_ = pv[i]; c_ = pv[i - bpp] if i >= bpp else 0
                    pa = abs(b_ - c_); pb_ = abs(a - c_); pc = abs(a + b_ - 2 * c_)
                    cur[i] = (cur[i] + (a if pa <= pb_ and pa <= pc else b_ if pb_ <= pc else c_)) & 255
            cur = np.frombuffer(bytes(cur), 'u1')
        out[y] = cur; prev = cur
    if ct == 3:
        if depth != 8: out = np.unpackbits(out, axis=1)[:, :w * depth].reshape(h, w, depth).dot(1 << np.arange(depth - 1, -1, -1)).astype('u1')
        rgb = plte[out]
        if trns is None: return rgb
        al = np.full(256, 255, 'u1'); al[:len(trns)] = np.frombuffer(trns, 'u1')
        return np.dstack([rgb, al[out]])
    if depth == 16: return np.frombuffer(out.tobytes(), '>u2').reshape(h, w, ch).astype('u2')
    return out.reshape(h, w, ch)

# ---- block helpers
def to_image(px, w, h, c):
    """px: N x 16 x c in block order."""
    bw, bh = max(1, (w + 3) // 4), max(1, (h + 3) // 4)
    return px.reshape(bh, bw, 4, 4, c).transpose(0, 2, 1, 3, 4).reshape(bh * 4, bw * 4, c)[:h, :w]

def to_blocks(img):
    """H x W x c to N x 16 x c, repeating the edge to fill a block."""
    h, w, c = img.shape; bw, bh = max(1, (w + 3) // 4), max(1, (h + 3) // 4)
    if (bh * 4, bw * 4) != (h, w): img = np.pad(img, ((0, bh * 4 - h), (0, bw * 4 - w), (0, 0)), mode='edge')
    return img.reshape(bh, 4, bw, 4, c).transpose(0, 2, 1, 3, 4).reshape(bh * bw, 16, c)

# ---- BC decoders
def bc1_decode(data):
    a = np.frombuffer(data, '<u2').reshape(-1, 4).astype(np.int32); c0, c1 = a[:, 0], a[:, 1]
    idx = a[:, 2].astype(np.int64) | a[:, 3].astype(np.int64) << 16
    def rgb(c):
        r, g, b = c >> 11, (c >> 5) & 63, c & 31
        return np.stack([(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)], 1)
    e0, e1 = rgb(c0), rgb(c1); four = (c0 > c1)[:, None]; n = len(a)
    pal = np.zeros((n, 4, 4), np.int32); pal[:, :, 3] = 255
    pal[:, 0, :3] = e0; pal[:, 1, :3] = e1
    pal[:, 2, :3] = np.where(four, (2 * e0 + e1 + 1) // 3, (e0 + e1) // 2)
    pal[:, 3, :3] = np.where(four, (e0 + 2 * e1 + 1) // 3, 0)
    pal[:, 3, 3] = np.where(four[:, 0], 255, 0)
    sel = (idx[:, None] >> (2 * np.arange(16))) & 3
    return pal[np.arange(n)[:, None], sel].astype('u1')

def bc4_decode(data):
    v = np.frombuffer(data, '<u8'); n = len(v)
    r0 = (v & np.uint64(255)).astype(np.int32); r1 = ((v >> np.uint64(8)) & np.uint64(255)).astype(np.int32)
    pal = np.zeros((n, 8), np.int32); pal[:, 0] = r0; pal[:, 1] = r1; many = r0 > r1
    for i in range(2, 8):
        a = ((8 - i) * r0 + (i - 1) * r1 + 3) // 7
        b = ((6 - i) * r0 + (i - 1) * r1 + 2) // 5 if i < 6 else np.full(n, 0 if i == 6 else 255)
        pal[:, i] = np.where(many, a, b)
    sel = ((v[:, None] >> np.uint64(16)) >> (np.uint64(3) * np.arange(16, dtype=np.uint64))) & np.uint64(7)
    return pal[np.arange(n)[:, None], sel.astype(np.int64)].astype('u1')[:, :, None]

def bc5_decode(data):
    a = np.frombuffer(data, 'u1').reshape(-1, 16)
    return np.concatenate([bc4_decode(a[:, :8].tobytes()), bc4_decode(a[:, 8:].tobytes())], 2)

BC7_MODES = [(3, 4, 0, 0, 4, 0, 1, 0, 3, 0), (2, 6, 0, 0, 6, 0, 0, 1, 3, 0), (3, 6, 0, 0, 5, 0, 0, 0, 2, 0), (2, 6, 0, 0, 7, 0, 1, 0, 2, 0),
             (1, 0, 2, 1, 5, 6, 0, 0, 2, 3), (1, 0, 2, 0, 7, 8, 0, 0, 2, 2), (1, 0, 0, 0, 7, 7, 1, 0, 4, 0), (2, 6, 0, 0, 5, 5, 1, 0, 2, 0)]
_P2 = """0011001100110011 0001000100010001 0111011101110111 0001001100110111 0000000100010011 0011011101111111 0001001101111111 0000000100110111
0000000000010011 0011011111111111 0000000101111111 0000000000010111 0001011111111111 0000000011111111 0000111111111111 0000000000001111
0000100011101111 0111000100000000 0000000010001110 0111001100010000 0011000100000000 0000100011001110 0000000010001100 0111001100110001
0011000100010000 0000100010001100 0110011001100110 0011011001101100 0001011111101000 0000111111110000 0111000110001110 0011100110011100
0101010101010101 0000111100001111 0101101001011010 0011001111001100 0011110000111100 0101010110101010 0110100101101001 0101101010100101
0111001111001110 0001001111001000 0011001001001100 0011101111011100 0110100110010110 0011110011000011 0110011010011001 0000011001100000
0100111001000000 0010011100100000 0000001001110010 0000010011100100 0110110010010011 0011011011001001 0110001110011100 0011100111000110
0110110011001001 0110001100111001 0111111010000001 0001100011100111 0000111100110011 0011001111110000 0010001011101110 0100010001110111"""
_P3 = """0011001102212222 0001001122112221 0000200122112211 0222002200110111 0000000011221122 0011001100220022 0022002211111111 0011001122112211
0000000011112222 0000111111112222 0000111122222222 0012001200120012 0112011201120112 0122012201220122 0011011211221222 0011200122002220
0001001101121122 0111001120012200 0000112211221122 0022002200221111 0111011102220222 0001000122212221 0000001101220122 0000110022102210
0122012200110000 0012001211222222 0110122112210110 0000011012211221 0022110211020022 0110011020022222 0011012201220011 0000200022112221
0000000211221222 0222002200120011 0011001200220222 0120012001200120 0000111122220000 0120120120120120 0120201212010120 0011220011220011
0011112222000011 0101010122222222 0000000021212121 0022112200221122 0022001100220011 0220122102201221 0101222222220101 0000212121212121
0101010101012222 0222011102220111 0002111200021112 0000211221122112 0222011101110222 0002111211120002 0110011001102222 0000000021122112
0110011022222222 0022001100110022 0022112211220022 0000000000002112 0002000100020001 0222122202221222 0101222222222222 0111201122012220"""
P2 = np.array([[int(c) for c in s] for s in _P2.split()], np.int32)
P3 = np.array([[int(c) for c in s] for s in _P3.split()], np.int32)
A2 = [15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15, 15,2,8,2,2,8,8,15,2,8,2,2,8,8,2,2, 15,15,6,8,2,8,15,15,2,8,2,2,2,15,15,6, 6,2,6,8,15,15,2,2,15,15,15,15,15,2,2,15]
A3A = [3,3,15,15,8,3,15,15,8,8,6,6,6,5,3,3, 3,3,8,15,3,3,6,10,5,8,8,6,8,5,15,15, 8,15,3,5,6,10,8,15,15,3,15,5,15,15,15,15, 3,15,5,5,5,8,5,10,5,10,8,13,15,12,3,3]
A3B = [15,8,8,3,15,15,3,8,15,15,15,15,15,15,15,8, 15,8,15,3,15,8,15,8,3,15,6,10,15,15,10,8, 15,3,15,10,10,8,9,10,6,15,8,15,3,6,6,8, 15,3,15,15,15,15,15,15,15,15,15,15,3,15,15,8]
WT = {2: np.array([0, 21, 43, 64]), 3: np.array([0, 9, 18, 27, 37, 46, 55, 64]), 4: np.array([0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64])}

def anchors(ns, part):
    return [0] if ns == 1 else [0, A2[part]] if ns == 2 else [0, A3A[part], A3B[part]]

def subsets(ns, part):
    return np.zeros(16, np.int32) if ns == 1 else P2[part] if ns == 2 else P3[part]

def _get(bits, pos, n):
    return bits[:, pos:pos + n].dot(1 << np.arange(n)) if n else np.zeros(len(bits), np.int64)

def bc7_decode(data):
    blocks = np.frombuffer(data, 'u1').reshape(-1, 16); N = len(blocks); out = np.zeros((N, 16, 4), 'u1')
    mode = np.full(N, 8)
    for m in range(7, -1, -1): mode[(blocks[:, 0] >> m) & 1 == 1] = m
    for m in range(8):
        sel = np.nonzero(mode == m)[0]
        if not len(sel): continue
        bits = np.unpackbits(blocks[sel], axis=1, bitorder='little').astype(np.int64)
        ns, pbn, rb, isb, cb, ab, epb, spb, ib, ib2 = BC7_MODES[m]
        pos = m + 1; part = _get(bits, pos, pbn); pos += pbn; rot = _get(bits, pos, rb); pos += rb; isel = _get(bits, pos, isb); pos += isb
        E = np.zeros((len(sel), 2 * ns, 4), np.int64)
        for c in range(3):
            for e in range(2 * ns): E[:, e, c] = _get(bits, pos, cb); pos += cb
        if ab:
            for e in range(2 * ns): E[:, e, 3] = _get(bits, pos, ab); pos += ab
        cbits, abits = cb, ab
        if epb:
            for e in range(2 * ns):
                E[:, e] = (E[:, e] << 1) | bits[:, pos:pos + 1]; pos += 1
            cbits += 1; abits += 1 if ab else 0
        if spb:
            for s in range(ns):
                E[:, 2 * s:2 * s + 2] = (E[:, 2 * s:2 * s + 2] << 1) | bits[:, pos:pos + 1, None]; pos += 1
            cbits += 1
        E[:, :, :3] = (E[:, :, :3] << (8 - cbits)) | (E[:, :, :3] >> (2 * cbits - 8))
        if ab: E[:, :, 3] = (E[:, :, 3] << (8 - abits)) | (E[:, :, 3] >> (2 * abits - 8))
        else: E[:, :, 3] = 255
        for p in np.unique(part):
            g = np.nonzero(part == p)[0]; S = subsets(ns, p); an = anchors(ns, p); gb = bits[g]; q = pos
            I = np.zeros((len(g), 16), np.int64); I2 = None
            for i in range(16):
                n = ib - (i in an); I[:, i] = _get(gb, q, n); q += n
            if ib2:
                I2 = np.zeros((len(g), 16), np.int64)
                for i in range(16):
                    n = ib2 - (i == 0); I2[:, i] = _get(gb, q, n); q += n
            wc = WT[ib][I]; wa = wc
            if ib2:
                wa = WT[ib2][I2]
                if m == 4:
                    swap = isel[g][:, None] == 1
                    wc, wa = np.where(swap, wa, wc), np.where(swap, wc, wa)
            e0 = E[g[:, None], 2 * S]; e1 = E[g[:, None], 2 * S + 1]
            px = np.zeros((len(g), 16, 4), np.int64)
            px[:, :, :3] = ((64 - wc[:, :, None]) * e0[:, :, :3] + wc[:, :, None] * e1[:, :, :3] + 32) >> 6
            px[:, :, 3] = ((64 - wa) * e0[:, :, 3] + wa * e1[:, :, 3] + 32) >> 6
            if rb:
                for r in (1, 2, 3):
                    k = rot[g] == r
                    px[k, :, r - 1], px[k, :, 3] = px[k, :, 3].copy(), px[k, :, r - 1].copy()
            out[sel[g]] = px
    return out

_C = 'rw9:0 gw9:0 bw9:0'
BC6_MODES = {  # low bits of the first byte: (mode bits, base bits, bit layout from the first bit after the mode)
    0b00: (2, 10, 'gy4 by4 bz4 ' + _C + ' rx4:0 gz4 gy3:0 gx4:0 bz0 gz3:0 bx4:0 bz1 by3:0 ry4:0 bz2 rz4:0 bz3'),
    0b01: (2, 7, 'gy5 gz4 gz5 rw6:0 bz0 bz1 by4 gw6:0 by5 bz2 gy4 bw6:0 bz3 bz5 bz4 rx5:0 gy3:0 gx5:0 gz3:0 bx5:0 by3:0 ry5:0 rz5:0'),
    0b00010: (5, 11, _C + ' rx4:0 rw10 gy3:0 gx3:0 gw10 bz0 gz3:0 bx3:0 bw10 bz1 by3:0 ry4:0 bz2 rz4:0 bz3'),
    0b00110: (5, 11, _C + ' rx3:0 rw10 gz4 gy3:0 gx4:0 gw10 gz3:0 bx3:0 bw10 bz1 by3:0 ry3:0 bz0 bz2 rz3:0 gy4 bz3'),
    0b01010: (5, 11, _C + ' rx3:0 rw10 by4 gy3:0 gx3:0 gw10 bz0 gz3:0 bx4:0 bw10 by3:0 ry3:0 bz1 bz2 rz3:0 bz4 bz3'),
    0b01110: (5, 9, 'rw8:0 by4 gw8:0 gy4 bw8:0 bz4 rx4:0 gz4 gy3:0 gx4:0 bz0 gz3:0 bx4:0 bz1 by3:0 ry4:0 bz2 rz4:0 bz3'),
    0b10010: (5, 8, 'rw7:0 gz4 by4 gw7:0 bz2 gy4 bw7:0 bz3 bz4 rx5:0 gy3:0 gx4:0 bz0 gz3:0 bx4:0 bz1 by3:0 ry5:0 rz5:0'),
    0b10110: (5, 8, 'rw7:0 bz0 by4 gw7:0 gy5 gy4 bw7:0 gz5 bz4 rx4:0 gz4 gy3:0 gx5:0 gz3:0 bx4:0 bz1 by3:0 ry4:0 bz2 rz4:0 bz3'),
    0b11010: (5, 8, 'rw7:0 bz1 by4 gw7:0 by5 gy4 bw7:0 bz5 bz4 rx4:0 gz4 gy3:0 gx4:0 bz0 gz3:0 bx5:0 by3:0 ry4:0 bz2 rz4:0 bz3'),
    0b11110: (5, 6, 'rw5:0 gz4 bz0 bz1 by4 gw5:0 gy5 by5 bz2 gy4 bw5:0 gz5 bz3 bz5 bz4 rx5:0 gy3:0 gx5:0 gz3:0 bx5:0 by3:0 ry5:0 rz5:0'),
    0b00011: (5, 10, _C + ' rx9:0 gx9:0 bx9:0'),
    0b00111: (5, 11, _C + ' rx8:0 rw10 gx8:0 gw10 bx8:0 bw10'),
    0b01011: (5, 12, _C + ' rx7:0 rw11 rw10 gx7:0 gw11 gw10 bx7:0 bw11 bw10'),
    0b01111: (5, 16, _C + ' rx3:0 rw15 rw14 rw13 rw12 rw11 rw10 gx3:0 gw15 gw14 gw13 gw12 gw11 gw10 bx3:0 bw15 bw14 bw13 bw12 bw11 bw10')}

def bc6_decode(data, signed=False):
    """BC6H to 16-bit RGBA, linear values above 1 clipped: for looking at, not for re-import."""
    if signed: raise SystemExit('signed BC6H: none ship, no decoder')
    blocks = np.frombuffer(data, 'u1').reshape(-1, 16); N = len(blocks); out = np.zeros((N, 16, 4), 'u2'); out[:, :, 3] = 65535
    first = blocks[:, 0].astype(np.int64); key = np.where((first & 3) < 2, first & 3, first & 31)
    for mval, (mb, wb, layout) in BC6_MODES.items():
        sel = np.nonzero(key == mval)[0]
        if not len(sel): continue
        bits = np.unpackbits(blocks[sel], axis=1, bitorder='little').astype(np.int64); pos = mb; F = {}; W = {}
        for tok in layout.split():
            name = tok[:2]; hi, _, lo = tok[2:].partition(':'); hi = int(hi); lo = int(lo) if lo else hi
            for b in (range(lo, hi + 1)):
                F[name] = F.get(name, 0) + (bits[:, pos] << b); pos += 1; W[name] = W.get(name, 0) + 1
        ns = 1 if mval & 3 == 3 and mb == 5 else 2
        delta = mval not in (0b11110, 0b00011); mask = (1 << wb) - 1
        E = np.zeros((len(sel), 2 * ns, 3), np.int64)
        for c, ch in enumerate('rgb'):
            E[:, 0, c] = F[ch + 'w']
            for e, f in enumerate('xyz'[:2 * ns - 1]):
                v = F[ch + f]
                if delta:
                    n = W[ch + f]; v = (v ^ (1 << (n - 1))) - (1 << (n - 1)); v = (F[ch + 'w'] + v) & mask
                E[:, e + 1, c] = v
        E = np.where(E == 0, 0, np.where(E == mask, 0xFFFF, ((E << 16) + 0x8000) >> wb)) if wb < 16 else E
        ib = 4 if ns == 1 else 3; shape = _get(bits, 77, 5) if ns == 2 else np.zeros(len(sel), np.int64); start = 65 if ns == 1 else 82
        for p in np.unique(shape):
            g = np.nonzero(shape == p)[0]; S = subsets(ns, p); an = anchors(ns, p); gb = bits[g]; q = start; I = np.zeros((len(g), 16), np.int64)
            for i in range(16):
                n = ib - (i in an); I[:, i] = _get(gb, q, n); q += n
            w = WT[ib][I][:, :, None]
            v = ((64 - w) * E[g[:, None], 2 * S] + w * E[g[:, None], 2 * S + 1] + 32) >> 6
            half = (v * 31) >> 6; f = half_to_float(half)
            out[sel[g][:, None, None], np.arange(16)[None, :, None], np.arange(3)[None, None, :]] = (np.clip(f, 0, 1) * 65535 + .5).astype('u2')
    return out

# ---- BC encoders
CHUNK = 16384

def _chunked(fn, bl):
    return b''.join(fn(bl[i:i + CHUNK]) for i in range(0, len(bl), CHUNK))

def _pca(P, m):
    """P N x 16 x C, m N x 16 weights: mean and main axis of the weighted pixels."""
    cnt = np.maximum(m.sum(1, keepdims=True), 1e-6); mean = (P * m[:, :, None]).sum(1) / cnt
    X = (P - mean[:, None, :]) * m[:, :, None]
    cov = np.einsum('nij,nik->njk', X, P - mean[:, None, :])
    v = np.ones((len(P), P.shape[2]), P.dtype)
    for _ in range(4):
        v = np.einsum('njk,nk->nj', cov, v)
        v /= np.maximum(np.sqrt((v * v).sum(1, keepdims=True)), 1e-6)
    return mean, v, cov

def _ends(P, mask):
    mean, v, _ = _pca(P, mask.astype(P.dtype))
    t = ((P - mean[:, None, :]) * v[:, None, :]).sum(2)
    lo = np.where(mask, t, np.inf).min(1, keepdims=True); hi = np.where(mask, t, -np.inf).max(1, keepdims=True)
    return mean + v * lo, mean + v * hi

def _lsq(P, m, a, e0, e1):
    """Best endpoints for pixel weights a (0 to 1) in subset m; blocks that can't be solved keep e0 and e1."""
    b = 1 - a; A = (m * b * b).sum(1); B = (m * a * b).sum(1); D = (m * a * a).sum(1)
    R0 = (P * (m * b)[:, :, None]).sum(1); R1 = (P * (m * a)[:, :, None]).sum(1)
    det = A * D - B * B; ok = det > 1e-3; d = np.where(ok, det, 1)[:, None]
    n0 = (D[:, None] * R0 - B[:, None] * R1) / d; n1 = (A[:, None] * R1 - B[:, None] * R0) / d
    return np.clip(np.where(ok[:, None], n0, e0), 0, 255), np.clip(np.where(ok[:, None], n1, e1), 0, 255)

def _expand(r, bits):
    return (r << (8 - bits)) | (r >> (2 * bits - 8))

def _quant(e, cb, pmode, force):
    """e: N x 2 x C floats. Returns raw ints, p bits (N x 2), and the values they decode to. force: blocks whose p bits must be 1."""
    if pmode is None:
        r = np.clip(np.rint(e * ((1 << cb) - 1) / 255), 0, (1 << cb) - 1).astype(np.int64)
        return r, np.zeros(e.shape[:2], np.int64), _expand(r, cb).astype(e.dtype)
    B = cb + 1; top = (1 << cb) - 1; rs = []; vs = []; errs = []
    for p in (0, 1):
        r = np.clip(np.rint((e * ((1 << B) - 1) / 255 - p) / 2), 0, top).astype(np.int64)
        v = _expand((r << 1) | p, B).astype(e.dtype)
        rs.append(r); vs.append(v); errs.append(((v - e) ** 2).sum(2))
    if pmode == 'shared': errs = [x.sum(1, keepdims=True).repeat(2, 1) for x in errs]
    pick = errs[1] < errs[0]
    if force is not None: pick = pick | force[:, None]
    return np.where(pick[:, :, None], rs[1], rs[0]), pick.astype(np.int64), np.where(pick[:, :, None], vs[1], vs[0])

def _assign(P, v0, v1, w):
    pal = np.floor(((64 - w)[None, :, None] * v0[:, None, :] + w[None, :, None] * v1[:, None, :] + 32) / 64)
    d = ((P[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(3)
    return d.argmin(2), d.min(2)

def _fit(P, mask, cb, pmode, w, force=None, rounds=2):
    """One subset. Returns raw N x 2 x C, p bits N x 2, indices N x 16, squared error N."""
    wf = w.astype(P.dtype) / 64; m = mask.astype(P.dtype); e0, e1 = _ends(P, mask); best = None
    for it in range(rounds + 1):
        r, pb_, v = _quant(np.stack([e0, e1], 1), cb, pmode, force)
        idx, d = _assign(P, v[:, 0], v[:, 1], w); err = (d * m).sum(1)
        if best is None: best = [r, pb_, idx, err]
        else:
            k = err < best[3]
            best = [np.where(k[:, None, None], r, best[0]), np.where(k[:, None], pb_, best[1]), np.where(k[:, None], idx, best[2]), np.where(k, err, best[3])]
        if it < rounds: e0, e1 = _lsq(P, m, wf[idx], e0, e1)
    return best

class Bits:
    def __init__(s, n): s.b = np.zeros((n, 128), 'u1'); s.p = 0
    def put(s, v, n):
        if n: s.b[:, s.p:s.p + n] = (np.asarray(v)[:, None] >> np.arange(n)) & 1; s.p += n

def bc7_pack(m, part, rot, isel, R, Pb, I, I2=None):
    """Order the endpoints so each anchor index has a clear top bit, then lay out the bits."""
    n = len(R); ns, pbn, rb, isb, cb, ab, epb, spb, ib, ib2 = BC7_MODES[m]
    R = R.copy(); Pb = Pb.copy(); I = I.copy(); out = np.zeros((n, 16), 'u1'); half = 1 << (ib - 1)
    groups = np.unique(part) if ns > 1 else [0]
    for p in groups:
        g = np.nonzero(part == p)[0] if ns > 1 else np.arange(n)
        S = subsets(ns, p); an = anchors(ns, p); Ig = I[g]; Rg = R[g]; Pg = Pb[g]
        for s in range(ns):
            k = Ig[:, an[s]] >= half
            if not k.any(): continue
            lim = 3 if m == 5 else Rg.shape[2]
            a, b = Rg[k, 2 * s, :lim].copy(), Rg[k, 2 * s + 1, :lim].copy()
            Rg[k, 2 * s, :lim], Rg[k, 2 * s + 1, :lim] = b, a
            a, b = Pg[k, 2 * s].copy(), Pg[k, 2 * s + 1].copy(); Pg[k, 2 * s], Pg[k, 2 * s + 1] = b, a
            for i in np.nonzero(S == s)[0]: Ig[k, i] = (1 << ib) - 1 - Ig[k, i]
        if ib2:    # mode 5's alpha has its own indices, so its own swap
            I2g = I2[g].copy(); k = I2g[:, 0] >= (1 << (ib2 - 1))
            a, b = Rg[k, 0, 3].copy(), Rg[k, 1, 3].copy(); Rg[k, 0, 3], Rg[k, 1, 3] = b, a
            I2g[k] = (1 << ib2) - 1 - I2g[k]
        w = Bits(len(g)); w.put(np.full(len(g), 1 << m), m + 1); w.put(np.full(len(g), p), pbn)
        w.put(np.zeros(len(g), np.int64) if rot is None else rot[g], rb)
        w.put(np.zeros(len(g), np.int64) if isel is None else isel[g], isb)
        for c in range(3):
            for e in range(2 * ns): w.put(Rg[:, e, c], cb)
        if ab:
            for e in range(2 * ns): w.put(Rg[:, e, 3], ab)
        if epb:
            for e in range(2 * ns): w.put(Pg[:, e], 1)
        if spb:
            for s in range(ns): w.put(Pg[:, 2 * s], 1)
        for i in range(16): w.put(Ig[:, i], ib - (i in an))
        if ib2:
            for i in range(16): w.put(I2g[:, i], ib2 - (i == 0))
        out[g] =np.packbits(w.b, axis=1, bitorder='little')
    return out

def _best_part(P, table, top=1):
    """For each block, the partition(s) with the least variance off each subset's main axis."""
    N = len(P); score = np.zeros((N, len(table)), P.dtype); total = None
    for k, S in enumerate(table):
        e = 0
        for s in range(S.max() + 1):
            m = np.broadcast_to((S == s).astype(P.dtype), (N, 16))
            mean, v, cov = _pca(P, m)
            tr = np.trace(cov, axis1=1, axis2=2)
            lam = np.einsum('nj,njk,nk->n', v, cov, v)
            e = e + np.maximum(tr - lam, 0)
        score[:, k] = e
    return np.argsort(score, 1)[:, :top]

def _bc7_chunk(bl):
    N = len(bl); P = bl.astype(np.float32); allm = np.ones((N, 16), bool)
    opaque = (bl[:, :, 3] == 255).all(1)
    r, p, idx, err = _fit(P, allm, 7, 'each', WT[4], force=opaque)
    out = bc7_pack(6, np.zeros(N, np.int64), None, None, r, p, idx); best = err
    # Alpha that varies on its own: mode 5 fits colour and alpha apart
    ka = np.nonzero(~opaque)[0]
    if len(ka):
        Pk = P[ka]; rc, _, ic, ec = _fit(Pk[:, :, :3], allm[ka], 7, None, WT[2])
        ra, _, ia, ea = _fit(Pk[:, :, 3:], allm[ka], 8, None, WT[2])
        R = np.concatenate([rc, ra], 2); o5 = bc7_pack(5, np.zeros(len(ka), np.int64), np.zeros(len(ka), np.int64), None, R, np.zeros((len(ka), 2), np.int64), ic, ia)
        e5 = ec + ea; k = e5 < best[ka]; out[ka[k]] = o5[k]; best[ka[k]] = e5[k]
    # Two subsets where one line of colour didn't fit
    cand = np.nonzero(best > 16 * 3.0)[0]
    for op in (True, False):
        sel = cand[opaque[cand] == op]
        if not len(sel): continue
        C = 3 if op else 4; Pc = P[sel][:, :, :C]
        for parts in _best_part(Pc, P2, 2).T:
            S = P2[parts]
            for mode, cb, pm, w in ((1, 6, 'shared', WT[3]), (3, 7, 'each', WT[2])) if op else ((7, 5, 'each', WT[2]),):
                R = np.zeros((len(sel), 4, C), np.int64); Pb_ = np.zeros((len(sel), 4), np.int64); I = np.zeros((len(sel), 16), np.int64); e = 0
                for s in (0, 1):
                    r_, p_, i_, er = _fit(Pc, S == s, cb, pm, w)
                    R[:, 2 * s:2 * s + 2] = r_; Pb_[:, 2 * s:2 * s + 2] = p_; I = np.where(S == s, i_, I); e = e + er
                k = e < best[sel]
                if k.any():
                    out[sel[k]] = bc7_pack(mode, parts[k], None, None, R[k], Pb_[k], I[k]); best[sel[k]] = e[k]
    return out.tobytes()

def bc7_encode(bl): return _chunked(_bc7_chunk, bl)

def _bc1_quant(e):
    r = np.clip(np.rint(e[:, 0] * 31 / 255), 0, 31).astype(np.int64); g = np.clip(np.rint(e[:, 1] * 63 / 255), 0, 63).astype(np.int64); b = np.clip(np.rint(e[:, 2] * 31 / 255), 0, 31).astype(np.int64)
    return (r << 11) | (g << 5) | b, np.stack([(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)], 1).astype(e.dtype)

def _bc1_chunk(bl):
    N = len(bl); P = bl[:, :, :3].astype(np.float32); hole = bl[:, :, 3] < 128; three = hole.any(1); m = ~hole
    m_any = m.copy(); m_any[~m.any(1)] = True
    e0, e1 = _ends(P, m_any)
    bestc = None
    for it in range(3):
        c0, v0 = _bc1_quant(e0); c1, v1 = _bc1_quant(e1); pal = np.zeros((N, 4, 3), np.float32)
        pal[:, 0] = v0; pal[:, 1] = v1
        pal[:, 2] = np.where(three[:, None], (v0 + v1) // 2, (2 * v0 + v1 + 1) // 3); pal[:, 3] = np.where(three[:, None], 0, (v0 + 2 * v1 + 1) // 3)
        d = ((P[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(3)
        if three.any(): d[three, :, 3] = np.inf
        idx = d.argmin(2); er = (d.min(2) * m).sum(1)
        if bestc is None: bestc = [c0, c1, idx, er]
        else:
            k = er < bestc[3]
            bestc = [np.where(k, c0, bestc[0]), np.where(k, c1, bestc[1]), np.where(k[:, None], idx, bestc[2]), np.where(k, er, bestc[3])]
        a = np.where(three[:, None], np.array([0, 1, .5, 0], np.float32)[idx], np.array([0, 1, 1 / 3, 2 / 3], np.float32)[idx])
        e0, e1 = _lsq(P, m_any.astype(np.float32), a, e0, e1)
    c0, c1, idx, _ = bestc; idx = idx.copy()
    # 4 colours need c0 > c1, 3 colours c0 <= c1; a swap maps 0<->1, and 2<->3 with 4 colours
    sw = (c0 < c1) & ~three | (c0 > c1) & three
    s4 = np.array([1, 0, 3, 2]); s3 = np.array([1, 0, 2, 3])
    idx = np.where(sw[:, None], np.where(three[:, None], s3[idx], s4[idx]), idx)
    a, b = np.where(sw, c1, c0), np.where(sw, c0, c1)
    idx = np.where(((a == b) & ~three)[:, None], 0, idx)
    if three.any(): idx = np.where(hole, 3, idx)
    bits = (idx << (2 * np.arange(16))).sum(1)
    out = np.zeros((N, 2), '<u4'); out[:, 0] = a | (b << 16); out[:, 1] = bits
    return out.tobytes()

def bc1_encode(bl): return _chunked(_bc1_chunk, bl)

BC4_STEPS = [(0, 0), (0, 1), (1, 0), (1, 1), (0, 2), (2, 0), (2, 2), (0, 4), (4, 0), (4, 4), (2, 4), (4, 2), (8, 8), (0, 8), (8, 0)]

def _bc4_chunk(v):
    """v: N x 16 ints."""
    N = len(v); lo = v.min(1); hi = v.max(1); best = np.full(N, np.inf); out0 = np.zeros(N, np.int64); out1 = np.zeros(N, np.int64); outi = np.zeros((N, 16), np.int64)
    def tryit(r0, r1, pal):
        nonlocal best, out0, out1, outi
        d = (v[:, :, None] - pal[:, None, :]) ** 2; idx = d.argmin(2); e = d.min(2).sum(1); k = e < best
        best = np.where(k, e, best); out0 = np.where(k, r0, out0); out1 = np.where(k, r1, out1); outi = np.where(k[:, None], idx, outi)
    for dh, dl in BC4_STEPS:
        r0 = np.clip(hi - dh, 0, 255); r1 = np.clip(lo + dl, 0, 255); good = r0 > r1
        r1g = np.where(good, r1, np.maximum(r0 - 1, 0)); r0g = np.where(good, r0, np.maximum(r1g + 1, r0))
        pal = np.zeros((N, 8), np.int64); pal[:, 0] = r0g; pal[:, 1] = r1g
        for i in range(2, 8): pal[:, i] = ((8 - i) * r0g + (i - 1) * r1g + 3) // 7
        tryit(r0g, r1g, pal)
    # Six values plus exact 0 and 255, for blocks with a hard edge to black or white
    v2lo = np.where(v == 0, 256, v).min(1); v2hi = np.where(v == 255, -1, v).max(1); edge = (lo == 0) | (hi == 255)
    if edge.any():
        r0 = np.clip(np.minimum(v2lo, v2hi), 0, 255); r1 = np.clip(np.maximum(v2lo, v2hi), 0, 255)
        pal = np.zeros((N, 8), np.int64); pal[:, 0] = r0; pal[:, 1] = r1
        for i in range(2, 6): pal[:, i] = ((6 - i) * r0 + (i - 1) * r1 + 2) // 5
        pal[:, 6] = 0; pal[:, 7] = 255
        nope = ~edge
        pal[nope] = 100000
        tryit(r0, r1, pal)
    return out0, out1, outi

def bc4_encode(bl):
    """bl: N x 16 x 1."""
    res = []
    for i in range(0, len(bl), CHUNK):
        v = bl[i:i + CHUNK, :, 0].astype(np.int64); r0, r1, idx = _bc4_chunk(v)
        q = np.zeros(len(v), np.uint64); q |= r0.astype(np.uint64) | (r1.astype(np.uint64) << np.uint64(8))
        for k in range(16): q |= idx[:, k].astype(np.uint64) << np.uint64(16 + 3 * k)
        res.append(q.astype('<u8').tobytes())
    return b''.join(res)

def bc5_encode(bl):
    a = np.frombuffer(bc4_encode(bl[:, :, 0:1]), 'u1').reshape(-1, 8); b = np.frombuffer(bc4_encode(bl[:, :, 1:2]), 'u1').reshape(-1, 8)
    return np.concatenate([a, b], 1).tobytes()

# ---- formats: canonical pixels are H x W x C
CODECS = {'BC1': (4, bc1_decode, bc1_encode), 'BC4': (1, bc4_decode, bc4_encode), 'BC5': (2, bc5_decode, bc5_encode), 'BC7': (4, bc7_decode, bc7_encode)}

def half_to_float(u):
    s = (u >> 15) & 1; e = (u >> 10) & 31; f = u & 1023
    v = np.where(e == 0, f * 2.0 ** -24, np.where(e == 31, np.inf, (1 + f / 1024.0) * 2.0 ** (e.astype(np.float64) - 15)))
    return np.where(s == 1, -v, v)

def decode_surface(h, data, w, hh):
    n = h['fname']
    if n in CODECS: return to_image(CODECS[n][1](data), w, hh, CODECS[n][0])
    if n == '8888': return np.frombuffer(data, 'u1').reshape(hh, w, 4)
    if n == '16161616_UNORM': return np.frombuffer(data, '<u2').reshape(hh, w, 4)
    if n == '16161616':
        f = half_to_float(np.frombuffer(data, '<u2').reshape(hh, w, 4))
        return (np.clip(np.nan_to_num(f), 0, 1) * 65535 + .5).astype('u2')
    if n in ('BC6HU', 'BC6HS'):
        return to_image(bc6_decode(data, n == 'BC6HS'), w, hh, 4)
    raise SystemExit('no decoder for format %s' % n)

def encode_surface(h, img):
    n = h['fname']
    if n in CODECS: return CODECS[n][2](to_blocks(img))
    if n == '8888': return img.astype('u1').tobytes()
    if n == '16161616_UNORM': return img.astype('<u2').tobytes()
    raise SystemExit('format %s can only be exported' % n)

def block_units(h, img):
    """Per-block view of pixels, for comparing old with new."""
    if h['bpb'] > 0: return to_blocks(img).reshape(max(1, (img.shape[0] + 3) // 4) * max(1, (img.shape[1] + 3) // 4), -1)
    return img.reshape(img.shape[0] * img.shape[1], -1)

def to_png_array(h, img):
    n = h['fname']
    if n == 'BC4': return img[:, :, 0]
    if n == 'BC5':
        x = img[:, :, 0].astype(np.float32) / 127.5 - 1; y = img[:, :, 1].astype(np.float32) / 127.5 - 1
        z = np.sqrt(np.clip(1 - x * x - y * y, 0, 1))
        return np.dstack([img, np.rint((z + 1) * 127.5).astype('u1')])
    if n in ('BC1', 'BC7', '8888') and (img[:, :, 3] == 255).all(): return img[:, :, :3]
    return img

def from_png_array(h, a):
    """Any PNG to this format's canonical channels: BC4 takes red, BC5 red and green, the rest RGBA."""
    if a.ndim == 2: a = a[:, :, None]
    wide = h['fname'] == '16161616_UNORM'
    if a.dtype == np.uint16 and not wide: a = ((a.astype(np.uint32) * 255 + 32767) // 65535).astype('u1')
    if wide and a.dtype == np.uint8: a = a.astype('u2') * 257
    c = a.shape[2]; top = 65535 if wide else 255
    if c <= 2: rgb = np.repeat(a[:, :, :1], 3, 2); al = a[:, :, 1:2] if c == 2 else np.full(a.shape[:2] + (1,), top, a.dtype)
    else: rgb = a[:, :, :3]; al = a[:, :, 3:4] if c == 4 else np.full(a.shape[:2] + (1,), top, a.dtype)
    n = h['fname']
    if n == 'BC4': return rgb[:, :, :1]
    if n == 'BC5': return rgb[:, :, :2]
    return np.dstack([rgb, al])

# ---- mips
_S2L = ((np.arange(256) / 255.0 + .055) / 1.055) ** 2.4; _S2L[:11] = (np.arange(11) / 255.0) / 12.92

def _area(img, w, h):
    """Area-weighted resize of a float image."""
    H, W = img.shape[:2]
    if (H, W) == (h * 2, w * 2): return (img[0::2, 0::2] + img[1::2, 0::2] + img[0::2, 1::2] + img[1::2, 1::2]) / 4
    for axis, old, new in ((0, H, h), (1, W, w)):
        if old == new: continue
        cum = np.concatenate([np.zeros_like(img.take([0], axis)), np.cumsum(img, axis)], axis)
        pos = np.linspace(0, old, new + 1); i0 = np.minimum(pos.astype(int), old - 1); fr = pos - i0
        shape = [1] * img.ndim; shape[axis] = -1
        at = cum.take(i0, axis) + fr.reshape(shape) * img.take(i0, axis)
        img = (np.diff(at, axis=axis)) / (old / new)
    return img

def downsample(h, img, w, hh):
    n = h['fname']; srgb = not (h['f37'] & F_LINEAR) and n in ('BC1', 'BC7', '8888')
    if img.dtype == np.uint16: return np.clip(np.rint(_area(img.astype(np.float64), w, hh)), 0, 65535).astype('u2')
    if not srgb: return np.clip(np.rint(_area(img.astype(np.float64), w, hh)), 0, 255).astype('u1')
    f = np.empty(img.shape, np.float64); f[:, :, :3] = _S2L[img[:, :, :3]]; f[:, :, 3] = img[:, :, 3]
    f = _area(f, w, hh); o = np.empty(f.shape, 'u1')
    c = np.clip(f[:, :, :3], 0, 1); o[:, :, :3] = np.clip(np.rint(255 * np.where(c <= .0031308, c * 12.92, 1.055 * np.maximum(c, 1e-9) ** (1 / 2.4) - .055)), 0, 255)
    o[:, :, 3] = np.clip(np.rint(f[:, :, 3]), 0, 255)
    return o

# ---- whole textures
def read_sub(t, r):
    st, level, s, off, sz, w, hh = r
    d = t.gvbh if st == 'h' else t.gvbm
    if d is None: return None
    return d[off:off + sz]

def top_level(h):
    subs = subresources(h)
    if h['hmips']: return [r for r in subs if r[0] == 'h' and r[1] == 0]
    return [r for r in subs if r[1] == 0]

def grid_join(tiles, cols, rows):
    return np.concatenate([np.concatenate(tiles[i * cols:(i + 1) * cols], 1) for i in range(rows)], 0)

def decode_top(t, h):
    tops = top_level(h)
    if tops[0][0] == 'h' and t.gvbh is None:
        tops = [r for r in subresources(h) if r[0] == 'g' and r[1] == h['hmips']]
    imgs = [decode_surface(h, read_sub(t, r), r[5], r[6]) for r in tops]
    return tops, imgs

def sha(b): return hashlib.sha1(b).hexdigest()

def cmd_export(source, texture, outdir, mips=False):
    t = open_tex(source, texture); h = parse_cvbm(t.cvbm); os.makedirs(outdir, exist_ok=True)
    if not check_sizes(h): print('warning: header sizes don\'t match this format\'s mip chain')
    if len(t.gvbm) != h['gsize']: print('warning: gvbm is %d bytes, header says %d' % (len(t.gvbm), h['gsize']))
    if h['hsize'] and t.gvbh is None: print('warning: no gvbh found; exporting the largest mip in the gvbm')
    tops, imgs = decode_top(t, h); base = t.inner[:-8]
    full = grid_join(imgs, h['cols'], h['rows'])
    png = os.path.join(outdir, base + '.png'); arr = to_png_array(h, full); png_write(png, arr)
    if mips:
        for r in subresources(h):
            if r[0] == 'h' and t.gvbh is None: continue
            png_write(os.path.join(outdir, '%s.mip%d.slice%d.png' % (base, r[1], r[2])), to_png_array(h, decode_surface(h, read_sub(t, r), r[5], r[6])))
    side = {'tool': 'srtex 1', 'name': h['name'], 'inner': t.inner, 'dir': t.dir, 'source': os.path.abspath(source), 'texture': texture,
            'host': t.host_entry['name'] if t.host_entry else None, 'host_dir': t.host_entry['dir'] if t.host_entry else None,
            'format': '%s (0x%X)' % (h['fname'], h['fmt']), 'size': [h['hw'] or h['w'], h['hh'] or h['h']], 'slice': [tops[0][5], tops[0][6]], 'grid': [h['cols'], h['rows']],
            'mips': [h['hmips'], h['gmips']], 'linear': bool(h['f37'] & F_LINEAR), 'cvbm': base64.b64encode(t.cvbm).decode(),
            'gvbm_sha1': sha(t.gvbm), 'gvbh_sha1': sha(t.gvbh) if t.gvbh else None, 'gvbh_from': t.gvbh_from, 'png_sha1': sha(arr.tobytes())}
    with open(os.path.join(outdir, base + '.srtex.json'), 'w') as f: json.dump(side, f, indent=1)
    print('%s %s %dx%d mips %d+%d grid %dx%d -> %s' % (base, h['fname'], side['slice'][0], side['slice'][1], h['hmips'], h['gmips'], h['cols'], h['rows'], png))

def average(h, top):
    """The header's four floats, about the mean of the pixels, 0 to 1: colour made linear when the texture is sRGB, alpha as is. Tested on 360 textures, see notes."""
    n = h['fname']
    if n == 'BC4': v = float(top[:, :, 0].mean() / 255); return (v, v, v, 1.0)
    if n == 'BC5':
        x = top[:, :, 0] / 127.5 - 1; y = top[:, :, 1] / 127.5 - 1
        return (float(top[:, :, 0].mean() / 255), float(top[:, :, 1].mean() / 255), float((np.sqrt(np.clip(1 - x * x - y * y, 0, 1)).mean() + 1) / 2), 1.0)
    rgb = top[:, :, :3]
    v = rgb.mean((0, 1)) / 255 if h['f37'] & F_LINEAR else _S2L[rgb].mean((0, 1))
    return (float(v[0]), float(v[1]), float(v[2]), float(top[:, :, 3].mean() / 255))

def rebuild_host(host, changes):
    """Replace entries of an archive in place: changes is name -> (raw size, stored bytes, compressed?). All else is kept, stale padding too."""
    nf, np_ = struct.unpack_from('<II', host, 0x10); do = struct.unpack_from('<Q', host, 0x40)[0]
    head = bytearray(host[:do]); names = 0x78 + nf * 0x30 + np_ * 8; rows = []
    for k in range(nf):
        no, po, off, sz, csz = struct.unpack_from('<QQQQq', host, 0x78 + k * 0x30)
        n = host[names + no:host.find(b'\0', names + no)].decode('latin1')
        rows.append((k, n, off, sz, csz))
    blob = bytearray(); total_raw = 0; total_stored = 0; comp = False
    for k, n, off, sz, csz in sorted(rows, key=lambda r: r[2]):
        body = host[do + off:do + off + (sz if csz < 0 else csz)]
        if n in changes:
            sz, body, compressed = changes[n]; csz = len(body) if compressed else -1
        struct.pack_into('<QQq', head, 0x78 + k * 0x30 + 0x10, len(blob), sz, csz)
        blob += body; total_raw += sz; total_stored += len(body); comp = comp or csz >= 0
    struct.pack_into('<QQQ', head, 0x20, do + len(blob), total_raw, total_stored if comp else 0)
    return bytes(head) + bytes(blob)

def cmd_import(sidecar, png, outdir, reuse=True, onto=None):
    s = json.load(open(sidecar)); cv = base64.b64decode(s['cvbm']); h = parse_cvbm(cv); base = s['inner'][:-8]; os.makedirs(outdir, exist_ok=True)
    t = None
    if reuse:
        t = open_tex(s['source'], s['texture'])
        if t.cvbm != cv or sha(t.gvbm) != s['gvbm_sha1'] or (s['gvbh_sha1'] and (t.gvbh is None or sha(t.gvbh) != s['gvbh_sha1'])):
            raise SystemExit('the source has changed since export')
    a = png_read(png); new = from_png_array(h, a); sw, sh = s['slice']; cols, rows = s['grid']
    if new.shape[0] != sh * rows or new.shape[1] != sw * cols:
        raise SystemExit('PNG is %dx%d, must be %dx%d: same size as the export' % (new.shape[1], new.shape[0], sw * cols, sh * rows))
    if h['fname'] in ('BC6HU', 'BC6HS', '16161616') and not reuse: raise SystemExit('%s can only be exported' % h['fname'])
    old = None
    if reuse:
        tops, imgs = decode_top(t, h); old = grid_join(imgs, cols, rows); old = from_png_array(h, to_png_array(h, old))
        if h['fname'] in ('BC6HU', 'BC6HS', '16161616') and (old != new).any(): raise SystemExit('%s can only be exported, and this PNG differs' % h['fname'])
    tile = lambda im, i: im[(i // cols) * sh:(i // cols + 1) * sh, (i % cols) * sw:(i % cols + 1) * sw]
    subs = subresources(h); bufs = {'h': bytearray(h['hsize']), 'g': bytearray(h['gsize'])}
    have_high = bool(h['hmips']) and (not reuse or t.gvbh is not None)
    stats = {'blocks': 0, 'reused': 0}; cur_new = {}; cur_old = {}
    for st, level, sl, off, sz, w, hh in subs:
        if st == 'h' and not have_high: continue
        prev_n = cur_new.get(sl);
        if prev_n is None:
            cur_new[sl] = tile(new, sl); cur_old[sl] = tile(old, sl) if old is not None else None
            if (cur_new[sl].shape[1], cur_new[sl].shape[0]) != (w, hh): raise SystemExit('slice size mismatch')
        elif (prev_n.shape[1], prev_n.shape[0]) != (w, hh):
            cur_new[sl] = downsample(h, prev_n, w, hh)
            if cur_old[sl] is not None: cur_old[sl] = downsample(h, cur_old[sl], w, hh)
        nimg, oimg = cur_new[sl], cur_old[sl]
        if oimg is not None:
            orig = read_sub(t, (st, level, sl, off, sz, w, hh)); same = (block_units(h, nimg) == block_units(h, oimg)).all(1)
            stats['blocks'] += len(same); stats['reused'] += int(same.sum())
            if same.all(): bufs[st][off:off + sz] = orig; continue
            enc = encode_surface(h, nimg)
            unit = h['bpb'] if h['bpb'] > 0 else -h['bpb']
            merged = np.where(same[:, None], np.frombuffer(orig, 'u1').reshape(-1, unit), np.frombuffer(enc, 'u1').reshape(-1, unit))
            bufs[st][off:off + sz] = merged.tobytes()
        else:
            bufs[st][off:off + sz] = encode_surface(h, nimg)
            stats['blocks'] += max(1, (w + 3) // 4) * max(1, (hh + 3) // 4)
    gvbm = bytes(bufs['g']); gvbh = bytes(bufs['h']) if have_high else None
    # The header's average colour, only when something changed
    ncv = bytearray(cv)
    if stats['reused'] != stats['blocks'] or not reuse:
        if h['bpb'] and h['fname'] in CODECS: struct.pack_into('<4f', ncv, 0x38, *average(h, new))
    ncv = bytes(ncv)
    report = {'inner': s['inner'], 'dir': s['dir'], 'files': {}, 'blocks': stats['blocks'], 'blocks_reused': stats['reused']}
    def emit(name, raw):
        with open(os.path.join(outdir, name), 'wb') as f: f.write(raw)
    emit(base + '.cvbm_pc', ncv); emit(base + '.gvbm_pc', gvbm)
    if gvbh is not None:
        emit(base + '.gvbh_pc', gvbh)
        st = t.gvbh_stored if t is not None and t.gvbh == gvbh and t.gvbh_stored is not None else pb.lz4_frame(gvbh)
        emit(base + '.gvbh_pc.lz4', st)
        report['files']['gvbh'] = {'dir': s['dir'], 'name': base + '.gvbh_pc', 'raw': len(gvbh), 'stored': len(st), 'same_as_original': t is not None and t.gvbh == gvbh, 'note': 'top-level archive entry; .lz4 is the stored form'}
    host = t.host if t is not None else None
    if host is None and s.get('host') and os.path.exists(s['source']):
        host = open_tex(s['source'], s['texture']).host
    if onto: host = open(onto, 'rb').read()
    if host is not None:
        rows_ = {r[0]: r for r in pb.read_pack(host)}; changes = {}; member = {}
        for name, raw in ((s['inner'], ncv), (base + '.gvbm_pc', gvbm)):
            r = rows_[name]; old_raw = get_entry_bytes(r[2], r[4])
            stored = r[2] if old_raw == raw else (pb.lz4_frame(raw) if r[4] >= 0 else raw)
            changes[name] = (len(raw), stored, r[4] >= 0)
            member[name] = {'raw': len(raw), 'stored': len(stored), 'stored_was': len(r[2])}
        out = rebuild_host(host, changes); emit(s['host'], out)
        report['files']['host'] = {'name': s['host'], 'dir': s['host_dir'], 'size': len(out), 'size_was': len(host), 'identical': out == host}
        c_, g_ = member[s['inner']], member[base + '.gvbm_pc']
        report['strh_member'] = {'id': '%016X' % pb.hash64((s['dir'] + '\\' + base + '.cvbm'), pb.exe_table()), 'c_stored_was': c_['stored_was'], 'g_stored_was': g_['stored_was'], 'c_stored': c_['stored'], 'g_stored': g_['stored'],
                                 'host_path': (s['host_dir'] + '\\' + s['host'])[:-len('.str2_pc')] if s.get('host_dir') else None}
        report['stored_changed'] = c_['stored'] != c_['stored_was'] or g_['stored'] != g_['stored_was']
    with open(os.path.join(outdir, base + '.import.json'), 'w') as f: json.dump(report, f, indent=1)
    print(json.dumps({k: report[k] for k in report if k not in ('files',)}, indent=None))
    return report

def strh_update(b, member_id, old_c, old_g, new_c, new_g, host_path=None):
    """Records listing this member get its two stored sizes changed and their stored total moved to match. A texture can be listed under
    several archives, each with its own copy: host_path (the archive's dir and name, no .str2_pc) limits this to the archive you replaced."""
    b = bytearray(b); key = struct.pack('<QII', member_id, old_c, old_g); n = 0; p = b.find(key); hp = host_path.encode('latin1') if host_path else None
    while p >= 0:
        q = p; found = False; mine = True
        for k in range(0, 4096):
            if q < 9: break
            total, cnt = struct.unpack_from('<II', b, q - 8)
            if b[q - 9] == 0x0A and k < cnt < 65536 and q + 16 * cnt <= len(b):
                if sum(sum(struct.unpack_from('<II', b, q + 16 * i + 8)) for i in range(cnt)) == total:
                    found = True
                    if hp is not None:     # 42 bytes of fixed fields lie between the path and the 0A
                        end = q - 9 - 42; mine = bytes(b[end - len(hp):end]).lower() == hp.lower()
                    if mine: struct.pack_into('<I', b, q - 8, total + (new_c - old_c) + (new_g - old_g))
                    break
            q -= 16
        if not found: raise SystemExit('stream record not understood at %X' % p)
        if mine: struct.pack_into('<II', b, p + 8, new_c, new_g); n += 1
        p = b.find(key, p + 16)
    return bytes(b), n

def cmd_strh(inp, out, report):
    j = json.load(open(report)); r = j['strh_member']; d = open(inp, 'rb').read()
    n, c = strh_update(d, int(r['id'], 16), r['c_stored_was'], r['g_stored_was'], r['c_stored'], r['g_stored'], r.get('host_path'))
    if not c: raise SystemExit('no record of %s lists this texture in %s' % (r.get('host_path'), inp))
    open(out, 'wb').write(n); print('%d record(s) updated -> %s' % (c, out))

def list_host(host, hostname, pat):
    for n, d, st, z, cs in pb.read_pack(host):
        if n.endswith('.cvbm_pc') and (pat is None or pat.search(n) or pat.search(hostname)):
            h = parse_cvbm(get_entry_bytes(st, cs))
            print('%-14s %5dx%-5d mips %d+%-2d grid %dx%d %s %s  gv %d gh %d  %s\\%s  [%s]' % (h['fname'], h['hw'] or h['w'], h['hh'] or h['h'], h['hmips'], h['gmips'], h['cols'], h['rows'],
                  'lin' if h['f37'] & F_LINEAR else 'srg', 'cube' if h['f36'] & F36_CUBE else '    ', h['gsize'], h['hsize'], d, n[:-8], hostname))

def cmd_list(source, regex, entry):
    pat = re.compile(regex, re.I) if regex else None
    if source.lower().endswith('.str2_pc'): return list_host(open(source, 'rb').read(), os.path.basename(source), pat)
    with open(source, 'rb') as f:
        for e in toc(f):
            if not e['name'].endswith('.str2_pc') or (entry and e['name'].lower() != entry.lower()): continue
            inner = toc(f, e['off']) if e['csz'] < 0 else None
            if inner is not None and not any(x['name'].endswith('.cvbm_pc') for x in inner): continue
            if inner is not None and pat is not None and not pat.search(e['name']) and not any(pat.search(x['name']) for x in inner if x['name'].endswith('.cvbm_pc')): continue
            list_host(stored_of(f, e) if e['csz'] < 0 else lz4_unframe(stored_of(f, e)), e['name'], pat)

def main():
    a = sys.argv[1:]; flag = lambda x: (x in a and not a.remove(x))
    if not a: raise SystemExit(__doc__)
    cmd = a[0]
    if cmd == 'list':
        en = None
        if '--entry' in a: i = a.index('--entry'); en = a[i + 1]; del a[i:i + 2]
        cmd_list(a[1], a[2] if len(a) > 2 else None, en)
    elif cmd == 'export': m = flag('--mips'); cmd_export(a[1], a[2], a[3], m)
    elif cmd == 'import':
        r = not flag('--no-reuse'); on = None
        if '--onto' in a: i = a.index('--onto'); on = a[i + 1]; del a[i:i + 2]
        cmd_import(a[1], a[2], a[3], r, on)
    elif cmd == 'strh': cmd_strh(a[1], a[2], a[3])
    else: raise SystemExit(__doc__)

if __name__ == '__main__':
    main()
