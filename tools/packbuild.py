"""packbuild.py: write SR5 packfiles (.vpp_pc, inner .str2_pc, .strh_pc) from loose bytes.
Layout read from the shipped dlc_preorder.vpp_pc. `selftest` rebuilds that pack from its own parts and compares bytes.
  python -I tools/packbuild.py selftest
"""
import struct, sys, zlib, os
MAGIC = b'\xce\x0a\x89\x51'
LZ4_HEAD = b'\x04\x22\x4d\x18\x40\x50\x77'   # frame: linked blocks, 256 KB, no checksums, as the game's
BLOCK = 256 * 1024

def lz4_block(src):
    """Greedy LZ4 block; matches may reach back into `src` only."""
    n = len(src); out = bytearray(); i = 0; anchor = 0; table = {}
    while i + 12 < n:
        k = src[i:i + 4]; c = table.get(k, -1); table[k] = i
        if c < 0 or i - c > 65535:
            i += 1; continue
        ml = 4
        while i + ml < n - 5 and src[c + ml] == src[i + ml]: ml += 1
        lit = i - anchor; m = ml - 4
        out.append((min(lit, 15) << 4) | min(m, 15))
        if lit >= 15:
            v = lit - 15
            while v >= 255: out.append(255); v -= 255
            out.append(v)
        out += src[anchor:i]
        out += struct.pack('<H', i - c)
        if m >= 15:
            v = m - 15
            while v >= 255: out.append(255); v -= 255
            out.append(v)
        for p in range(i + 1, min(i + ml, n - 4)): table[src[p:p + 4]] = p
        i += ml; anchor = i
    lit = n - anchor
    out.append(min(lit, 15) << 4)
    if lit >= 15:
        v = lit - 15
        while v >= 255: out.append(255); v -= 255
        out.append(v)
    out += src[anchor:]
    return bytes(out)

def lz4_frame(data):
    out = bytearray(LZ4_HEAD)
    for p in range(0, len(data), BLOCK):
        chunk = data[p:p + BLOCK]; c = lz4_block(chunk)
        if len(c) < len(chunk): out += struct.pack('<I', len(c)) + c
        else: out += struct.pack('<I', len(chunk) | 0x80000000) + chunk
    return bytes(out + b'\0\0\0\0')

def lz4_unframe(d):
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
            for k in range(ml): out.append(out[s + k])

# Stronger LZ4 for files whose stored size matters: hash chains, one step of lazy matching, and linked blocks (matches may reach
# into the previous block, up to 64 KB back), as the game's own files are built. Sequences are kept as (literal start, literal
# length, offset, match length) so a frame can be grown to an exact stored size by splitting one long match.
def _lz4_sequences(data, start, end, depth):
    seqs = []; head = {}; prev = {}; i = start; anchor = start; last = end - 12; limit = end - 5
    ins = [max(0, start - 65535)]
    def upto(q):
        # adds every position before q to the chains; a position is searched before it is added, so no match points at itself
        p = ins[0]
        while p < q:
            k = data[p:p + 4]; h = head.get(k)
            if h is not None: prev[p] = h
            head[k] = p; p += 1
        ins[0] = max(ins[0], q)
    upto(start)
    def best(p):
        k = data[p:p + 4]; c = head.get(k); bl = bo = 0; n = 0; cap = limit - p
        while c is not None and n < depth and p - c <= 65535:
            if data[c + bl:c + bl + 1] == data[p + bl:p + bl + 1]:
                l = 4
                while l < cap:
                    s = min(cap - l, 64)
                    if data[c + l:c + l + s] == data[p + l:p + l + s]: l += s
                    else:
                        while l < cap and data[c + l] == data[p + l]: l += 1
                        break
                if l > bl: bl, bo = l, p - c
                if l >= cap: break
            c = prev.get(c); n += 1
        return bl, bo
    while i < last:
        upto(i); l, o = best(i)
        if l < 4:
            i += 1; continue
        if i + 1 < last:
            upto(i + 1); l2, o2 = best(i + 1)
            if l2 > l + 1: i += 1; l, o = l2, o2
        seqs.append((anchor, i - anchor, o, l))
        i += l; anchor = i
        upto(min(i, end - 4))
    seqs.append((anchor, end - anchor, 0, 0))
    return seqs

def _lz4_len(v, out):
    v -= 15
    while v >= 255: out.append(255); v -= 255
    out.append(v)

def _lz4_encode(data, seqs):
    out = bytearray()
    for ls, ll, off, ml in seqs:
        m = ml - 4 if ml else 0
        out.append((min(ll, 15) << 4) | (min(m, 15) if ml else 0))
        if ll >= 15: _lz4_len(ll, out)
        out += data[ls:ls + ll]
        if ml:
            out += struct.pack('<H', off)
            if m >= 15: _lz4_len(m, out)
    return bytes(out)

def _lz4_cost(ll, ml):
    c = 1 + ll + (0 if ll < 15 else (ll - 15) // 255 + 1)
    return c + (0 if not ml else 2 + (0 if ml - 4 < 15 else (ml - 19) // 255 + 1))

def _lz4_grow(data, seqs, extra):
    """Make the encoded sequences exactly `extra` bytes longer by moving the starts of long matches into their literals.
    The match keeps its offset: its first k bytes become literals, and the rest still copies from the same distance back."""
    t = list(seqs); need = extra
    for j in sorted(range(len(t) - 1), key=lambda j: -t[j][3]):
        if need == 0: break
        ls, ll, off, ml = t[j]
        # at least 8 left, so a match still starts 13+ bytes before the block's end (it ends 5+ before), as LZ4 requires 12
        if ml < 9: continue
        was = _lz4_cost(ll, ml); pick = None
        for k in range(min(ml - 8, need + 2), 0, -1):
            d = _lz4_cost(ll + k, ml - k) - was
            if d == need: pick = (k, d); break
            if d < need and pick is None: pick = (k, d)
        if pick:
            t[j] = (ls, ll + pick[0], off, ml - pick[0]); need -= pick[1]
    return t, extra - need

def lz4_frame_hc(data, depth=32, target=None):
    """LZ4 frame with linked blocks. With `target`, the frame is grown to exactly that many bytes, or None if it can't be."""
    blocks = []
    for p in range(0, len(data), BLOCK):
        blocks.append(_lz4_sequences(data, p, min(p + BLOCK, len(data)), depth))
    def frame(bl):
        out = bytearray(LZ4_HEAD)
        for k, s in enumerate(bl):
            c = _lz4_encode(data, s); p = k * BLOCK; chunk = data[p:p + BLOCK]
            if len(c) < len(chunk): out += struct.pack('<I', len(c)) + c
            else: out += struct.pack('<I', len(chunk) | 0x80000000) + chunk
        return bytes(out + b'\0\0\0\0')
    f = frame(blocks)
    if target is None or len(f) == target: return f
    if len(f) > target: return None
    need = target - len(f)
    for k in range(len(blocks) - 1, -1, -1):
        if need == 0: break
        blocks[k], got = _lz4_grow(data, blocks[k], need); need -= got
    f = frame(blocks)
    return f if len(f) == target else None

def packfile(files, flags=0, word8=None, stamp=0x64ECF028, names_alloc=None):
    """files: (name, dir, raw, stored). stored is None for an uncompressed entry, else the bytes as stored."""
    # The game decompresses an entry only when the archive's flags have bit 0x1 too (+D84D00); without it LZ4 bytes are read as data.
    if not flags & 1 and any(f[3] is not None for f in files): raise ValueError('compressed entries need header flag 0x1; store them raw')
    names = bytearray(); seen = {}; rows = []; dirs = []
    def add(s):
        if s not in seen:
            seen[s] = len(names); names.extend(s.encode('latin1') + b'\0')
        return seen[s]
    off = 0; total_raw = 0; total_stored = 0; blob = bytearray()
    for name, d, raw, stored in files:
        no = add(name); new_dir = d not in seen; po = add(d)
        if new_dir: dirs.append(po)
        body = raw if stored is None else stored
        rows.append(struct.pack('<QQQQqII', no, po, off, len(raw), -1 if stored is None else len(stored), 0x10000 if stored is None else 0x10001, 0))
        blob += body; off += len(body); total_raw += len(raw); total_stored += len(body)
    dataoff = 0x78 + len(rows) * 0x30 + len(dirs) * 8 + len(names)
    size = dataoff + len(blob)
    if names_alloc is None: names_alloc = len(rows) * 0x30 + len(dirs) * 8   # +18: size of the two tables
    if word8 is None: word8 = zlib.crc32(bytes(names)) & 0xFFFFFFFF
    comp = any(f[3] is not None for f in files)
    h = struct.pack('<4sIIIIIII', MAGIC, 0x11, word8, flags, len(rows), len(dirs), names_alloc, len(names))
    h += struct.pack('<QQQQQ', size, total_raw, total_stored if comp else 0, stamp, dataoff)
    h += bytes(0x78 - len(h))
    return h + b''.join(rows) + b''.join(struct.pack('<Q', p) for p in dirs) + bytes(names) + bytes(blob)

def hash64(s, table):
    c = 0
    for ch in s.lower().encode('latin1'):
        c = table[(c ^ ch) & 0xFF] ^ (c >> 8)
    return c

def strh(path, resource_hash, raw_size, stored_size, data_offset, kind):
    """Streaming header beside a .tfe_pad.str2_pc. `path` ends .tfe_pad. `kind` is a u16 whose meaning isn't known
    (1 to 9 in the shipped files): copy it from the table this one was derived from."""
    p = path.encode('latin1'); hb = struct.pack('<Q', resource_hash)
    tail = b'\x07' + hb + bytes(10) + b'\x01\0\0\0\0\0\0' + struct.pack('<IIHH', raw_size, 0, kind, 0xFFFF)
    tail += struct.pack('<I', data_offset) + b'\x0a' + struct.pack('<II', stored_size, 1) + hb + struct.pack('<IIHH', stored_size, 0, kind, 0xFFFF) + b'\x83\0'
    head = bytes.fromhex('edfeefbe2100000001000000000000000' + '10c00') + b'Gamelib info'
    head += b'\x07\x06\0\x08\0.tfe_pad\0\x07\0.tfe_pc\x01\x08\0.tfe_pad\x01\x07\0.tfe_pc\x07\x08\0.tfe_pad\x07\x07\0.tfe_pc'
    body = bytes(4) + struct.pack('<H', len(p)) + p + tail
    return head + b'\x01' + struct.pack('<I', len(body) + 5) + body

def table_str2(path_dir, name_pad, raw, word8=None, stamp=0x64ECEFB0, stored=None):
    """Inner archive holding one table. Returns (bytes, stored_size, data_offset)."""
    stored = lz4_frame(raw) if stored is None else stored
    b = packfile([(name_pad, path_dir, raw, stored)], flags=0x5001, word8=word8, stamp=stamp)
    return b, len(stored), struct.unpack_from('<Q', b, 0x40)[0]

def exe_table(exe=r'C:\Program Files\Epic Games\SaintsRow\sr5\SaintsRow_DX12.exe'):
    """The 256-entry CRC64 table at +2A26530, read through the PE section map."""
    d = open(exe, 'rb').read(); pe = struct.unpack_from('<I', d, 0x3C)[0]
    ns = struct.unpack_from('<H', d, pe + 6)[0]; opt = struct.unpack_from('<H', d, pe + 20)[0]
    for i in range(ns):
        va_size, va, raw_size, raw = struct.unpack_from('<IIII', d, pe + 24 + opt + i * 40 + 8)
        if va <= 0x2A26530 < va + raw_size: return struct.unpack_from('<256Q', d, raw + 0x2A26530 - va)

def string_crc(s, exe=r'C:\Program Files\Epic Games\SaintsRow\sr5\SaintsRow_DX12.exe'):
    """The game's string_crc (+16A2550): CRC32 from the table at +2A26EF0, init 0, no final xor, case kept."""
    d = open(exe, 'rb').read(); pe = struct.unpack_from('<I', d, 0x3C)[0]
    ns = struct.unpack_from('<H', d, pe + 6)[0]; opt = struct.unpack_from('<H', d, pe + 20)[0]
    for i in range(ns):
        va_size, va, raw_size, raw = struct.unpack_from('<IIII', d, pe + 24 + opt + i * 40 + 8)
        if va <= 0x2A26EF0 < va + raw_size:
            t = struct.unpack_from('<256I', d, raw + 0x2A26EF0 - va)
    c = 0
    for ch in s.encode('latin1'):
        c = (c >> 8) ^ t[(c ^ ch) & 0xFF]
    return c

SCRIBE_TYPE = b'\x01\x06\0Scribe\x0c\x09\0\x0b\0.scribe_pad\0\x0a\0.scribe_pc\0\x07\0.scribe\x01\x0b\0.scribe_pad\x01\x0a\0.scribe_pc\x01\x07\0.scribe\x07\x0b\0.scribe_pad\x07\x0a\0.scribe_pc\x07\x07\0.scribe'

def strh_record(path, resource_hash, raw_size, stored_size, data_offset, kind, type_id):
    """One stream header record. type_id is the resource type's number in the file's type list."""
    p = path.encode('latin1'); hb = struct.pack('<Q', resource_hash)
    tail = bytes([type_id]) + hb + bytes(10) + b'\x01\0\0\0\0\0\0' + struct.pack('<IIHH', raw_size, 0, kind, 0xFFFF)
    tail += struct.pack('<I', data_offset) + b'\x0a' + struct.pack('<II', stored_size, 1) + hb + struct.pack('<IIHH', stored_size, 0, kind, 0xFFFF) + b'\x83\0'
    body = bytes(4) + struct.pack('<H', len(p)) + p + tail
    return b'\x01' + struct.pack('<I', len(body) + 5) + body

def strh_scribe(path, resource_hash, raw_size, stored_size, data_offset):
    return bytes.fromhex('edfeefbe2100000001000000' '00000000') + SCRIBE_TYPE + strh_record(path, resource_hash, raw_size, stored_size, data_offset, 1, 0x0C)

def scribe_table(template, rows):
    """A language text file: `template` is a shipped one, whose head and field list are kept; rows are (key, text)."""
    head_end = 0x150
    size = struct.unpack_from('<I', template, 0x148)[0]
    tail = template[head_end + size - 8:]
    body = bytearray()
    for key, text in rows:
        k = key.encode('latin1'); t = (text or '').encode('utf8')
        r = bytearray(struct.pack('<IIIIII', 0, 0x01000000, string_crc(key), 0, 0, 0)) + struct.pack('<I', len(k) + 1) + k + b'\0'
        r += bytes(-len(r) % 8)
        if text is not None:
            r += struct.pack('<II', len(t), 0x0E002000) + t
            r += bytes(-len(r) % 8)
        r[0:4] = struct.pack('<I', len(r))
        body += r
    head = bytearray(template[:head_end])
    head[0x148:0x14C] = struct.pack('<I', len(body) + 8)
    return bytes(head) + bytes(body) + tail

def scribe_rows(b):
    """Rows of a text file, for testing."""
    size = struct.unpack_from('<I', b, 0x148)[0]; p = 0x150; end = 0x150 + size - 8; rows = []
    while p < end:
        rs = struct.unpack_from('<I', b, p)[0]
        n = struct.unpack_from('<I', b, p + 24)[0]
        key = b[p + 28:p + 28 + n - 1].decode('latin1')
        q = p + 28 + n; q += -q % 8
        if q >= p + rs: rows.append((key, None))
        else:
            ln = struct.unpack_from('<I', b, q)[0]
            rows.append((key, b[q + 8:q + 8 + ln].decode('utf8')))
        p += rs
    return rows

def read_pack(b):
    nf, np_, _, ns = struct.unpack_from('<4I', b, 0x10)
    do = struct.unpack_from('<Q', b, 0x40)[0]
    names = 0x78 + nf * 0x30 + np_ * 8
    def nm(o):
        e = b.find(b'\0', names + o); return b[names + o:e].decode('latin1')
    out = []
    for k in range(nf):
        no, po, off, sz, csz, fl = struct.unpack_from('<QQQQqI', b, 0x78 + k * 0x30)
        out.append((nm(no), nm(po), b[do + off:do + off + (sz if csz < 0 else csz)], sz, csz))
    return out

def masked(b):
    """The last word of each entry is padding with stale bytes in the shipped files."""
    m = bytearray(b); nf = struct.unpack_from('<I', b, 0x10)[0]
    for k in range(nf): m[0x78 + k * 0x30 + 0x2C:0x78 + k * 0x30 + 0x30] = bytes(4)
    return bytes(m)

def selftest(path=r'C:\Program Files\Epic Games\SaintsRow\sr5\data\dlc_preorder\dlc_preorder.vpp_pc'):
    orig = open(path, 'rb').read(); bad = 0
    # lz4 round trip on real data
    for name, d, body, sz, csz in read_pack(orig):
        if name.endswith('.str2_pc'):
            (n2, d2, s2, z2, c2), = read_pack(body)
            raw = lz4_unframe(s2)
            again = lz4_unframe(lz4_frame(raw))
            if again != raw or len(raw) != z2: print('lz4 round trip FAILED', n2); bad += 1
            w8, stamp = struct.unpack_from('<I', body, 8)[0], struct.unpack_from('<Q', body, 0x38)[0]
            rebuilt, _, _ = table_str2(d2, n2, raw, w8, stamp, stored=s2)
            if masked(rebuilt) != masked(body):
                print('str2 differs', name, [hex(i) for i in range(min(len(rebuilt), len(body))) if rebuilt[i] != body[i]][:8], len(rebuilt), len(body)); bad += 1
    contents = {n: (d, body) for n, d, body, sz, csz in read_pack(orig)}
    for n, (d, body) in contents.items():
        if n.endswith('.strh_pc'):
            pad = n[:-len('.strh_pc')]
            s_d, s_b = contents[pad + '.str2_pc']
            (n2, d2, s2, z2, c2), = read_pack(s_b)
            raw = lz4_unframe(s2)
            canon = (d2 + '\\' + n2)[:-len('_pad')]
            mine = strh(d2 + '\\' + n2, hash64(canon, exe_table()), z2, c2, struct.unpack_from('<Q', s_b, 0x40)[0], struct.unpack_from('<H', body, len(body) - 6)[0])
            if mine != body:
                print('strh differs', n, len(mine), len(body), [hex(i) for i in range(min(len(mine), len(body))) if mine[i] != body[i]][:10]); bad += 1
    files = [(n, d, body, None) for n, d, body, sz, csz in read_pack(orig)]
    w8 = struct.unpack_from('<I', orig, 8)[0]; stamp = struct.unpack_from('<Q', orig, 0x38)[0]; alloc = struct.unpack_from('<I', orig, 0x18)[0]
    rebuilt = packfile(files, flags=0, word8=w8, stamp=stamp, names_alloc=alloc)
    if masked(rebuilt) != masked(orig):
        diff = [hex(i) for i in range(min(len(rebuilt), len(orig))) if rebuilt[i] != orig[i]][:12]
        print('outer differs at', diff, len(rebuilt), len(orig)); bad += 1
    # Text files: rebuild the shipped ones from their rows, and find a stream record we'd write inside the shipped header
    d1 = r'C:\\Program Files\\Epic Games\\SaintsRow\\sr5\\data\\dlc_01\\dlc_01.vpp_pc'
    pk = open(d1, 'rb'); h = pk.read(0x78)
    nf, np_, _, ns = struct.unpack_from('<4I', h, 0x10); do = struct.unpack_from('<Q', h, 0x40)[0]
    ents = pk.read(nf * 0x30); pk.read(np_ * 8); names = pk.read(do - pk.tell())
    consolidated = None; texts = []
    for k in range(nf):
        no, po, off, sz, csz, fl = struct.unpack_from('<QQQQqI', ents, k * 0x30)
        n = names[no:names.find(b'\0', no)].decode('latin1')
        if n == 'dlc_01.strh_pc' or '.en.scribe_pad.str2_pc' in n:
            pk.seek(do + off); raw = pk.read(sz if csz < 0 else csz)
            if csz >= 0: raw = lz4_unframe(raw)
            if n == 'dlc_01.strh_pc': consolidated = raw
            else: texts.append((n, raw))
    pk.close(); t64 = exe_table(); done = 0
    if SCRIBE_TYPE[1:] not in consolidated: print('scribe type block not found in shipped header'); bad += 1
    for n, raw in texts:
        (n2, d2, s2, z2, c2), = read_pack(raw)
        t = lz4_unframe(s2)
        if scribe_table(t, scribe_rows(t)) != t: print('text rebuild differs', n2); bad += 1
        pth = d2 + '\\' + n2; hsh = hash64(pth[:-len('_pad')], t64)
        at = consolidated.find(pth.encode() + b'\x0c')
        kind = struct.unpack_from('<H', consolidated, at + len(pth) + 1 + 8 + 10 + 7 + 8)[0]   # 1 to 12 in the shipped files, meaning unknown
        rec = strh_record(pth, hsh, z2, c2, struct.unpack_from('<Q', raw, 0x40)[0], kind, 0x0C)
        if consolidated[at - 11:at - 11 + len(rec)] != rec: print('stream record differs', n2); bad += 1
        done += 1
    print('text files checked', done)
    print('selftest', 'OK: outer, all inner archives and all strh byte-identical (entry padding aside)' if not bad else 'FAILED %d' % bad)
    return bad

if __name__ == '__main__':
    if sys.argv[1:] == ['selftest']:
        for n, want in (('sedan_01b', 0x1992D148), ('sedan_01b_reward', 0x02DFD25F), ('inventory_weapon_info', 0x466020EC)):
            print(n, '%08X' % string_crc(n), 'OK' if string_crc(n) == want else 'want %08X' % want)
        sys.exit(selftest())
