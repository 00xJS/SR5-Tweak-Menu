"""plate_maker.py: your own licence plate texts for Saints Row (2022). Draws them into glyph row 0 of the plate atlas, which the
game's own seeds never reach, and builds the patch and the seed list the menu reads. See research_license_plates.md.
  python -I tools/plate_maker.py [--install] [--out DIR] [--file PLATES.txt] [--font FACE[:WEIGHT]] PLATE ...
PLATE is the text as a plate shows it: 3 characters, a space, 4 characters ("00X JS"). Text with no space is centred ("00xJS"
puts a blank either side). Case is kept: lower case letters are drawn to match the plate font. Shorter groups get blank cells at the end,
and _ is a blank cell anywhere ("_7_ _JS_"). Add =BACKGROUND to ask for one: cougar, owl, cactus, fire, or cougar-jr and so on
for the JimRob's frame, or 0 to 7. PLATES.txt holds one PLATE a line; # starts a comment.
Writes to DIR (default %TEMP%\\sr5_plate_maker):
  data\\sr_boot\\sr_boot_patch.vpp_pc  goes in sr5\\data\\sr_boot\\: the atlas's high mips with the new row 0, stored raw, flags 0x10000
  custom_plates.txt                   goes in TweakMenu\\: TEXT|seed|background a line, read by SRTweakMenu\\plates.lua
  preview.png                         row 0 as built, above the shipped rows, the drawn letters between shipped H's, and each plate
  report.json, work\\                  layout, seeds, block counts, and the texture exported back from the patch
Reads the game's files only. Needs numpy; draws letters the atlas lacks (I M N Q W, punctuation) with GDI, so Windows only.
--install copies the patch and the list into the game (close the game first; they're read at boot). Seen in the game
2026-11-03: 00X JS and SR5 MENU on a car's plate, so sr_boot_patch is read although sr_boot is mounted with the merge flag off."""
import argparse, collections, ctypes, json, os, struct, sys, tempfile
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import packbuild as pb
import srtex

DATA = r'C:\Program Files\Epic Games\SaintsRow\sr5\data'
SOURCE = DATA + r'\dlc_01\dlc_01.vpp_pc'        # a car archive with the atlas header and low mips; srtex finds the high mips in sr_boot
TEXTURE = 'veh_car_4dr_two_fronts.cprefab_pc.str2_pc:veh_license_plates_dfa'
GVBH, GDIR = 'veh_license_plates_dfa.gvbh_pc', 'data\\sr_boot\\vehicles\\textures'
ROWS = ['6259307072931981', '4290146576189685', '7393175698116962', '8460951804163385',     # alpha, glyph rows 0 to 7
        'S4FCSGOC3U07JOGD', 'L6S5HF9VJASUB862', 'R2SEYXZAVF005TSB', 'LPFU5ECZ17D8B6PK']
BGS = ['cougar', 'owl', 'cactus', 'fire', "cougar, JimRob's", "owl, JimRob's", "cactus, JimRob's", "fire, JimRob's"]
CW, CH = 32, 64                                 # glyph cell at mip 0; mip 1 halves it
BLANK = ' '
TEST_SEED = 1.0                                 # the material's other constant: the shader uses seed + 1.0
K_ROW, K_A3, K_C4 = 1.924406, 6.283185, 2.362988
NOTE_MERGE = ('sr_boot is registered by +14E1B70 with arg 2 = 0 (xor edx,edx at +14E1C26; [+41EB348] is settings +0x82B8 = "data\\sr_boot", '
              'set at +BCAB72). +14FA1C0 passes arg2 && (arg4 in 0..1) to +14F9880 as the merge flag, so sr_boot_patch is opened as its own '
              'archive (+D97650), not merged into sr_boot (+D99570) as dlc_01, sr_city and dlc_preorder are. Whether a lookup then prefers it is unread.')

# ---- plates
def centred(text):
    """Text with no space, centred on the plate: the gap after the 3-group is fixed, so blanks go either side of it to balance
    ("00xJS" -> "_00", "xJS_"). Cells sit at 0 1 2, the gap, then 4 5 6 7; the plate's middle is 3.5."""
    n = len(text)
    best = None
    for lead in range(max(0, 3 - n), min(3, 7 - n) + 1):
        k = 3 - lead                                        # characters left of the gap
        xs = list(range(lead, 3)) + list(range(4, 4 + n - k))
        off = abs((xs[0] + xs[-1]) / 2 - 3.5)
        if best is None or off < best[0]: best = (off, '_' * lead + text[:k], text[k:])
    return best[1], best[2]

def parse_plate(spec):
    text, _, bg = spec.partition('=')
    text = text.strip()                                     # case kept: capitals from the atlas, lower case drawn to match
    if text.count(' ') > 1: raise SystemExit('%r: one space only, between the 3 and the 4; use _ for a blank cell' % spec)
    if ' ' not in text and len(text) > 7: raise SystemExit('%r: a plate holds 7 characters' % spec)
    left, right = text.split(' ') if ' ' in text else centred(text)
    if len(left) > 3 or len(right) > 4 or not (left + right).strip('_'): raise SystemExit('%r: a plate is up to 3 characters, a space, up to 4' % spec)
    bad = [c for c in left + right if not ('!' <= c <= '~') or c in '|=']
    if bad: raise SystemExit('%r: can\'t use %r' % (spec, ''.join(bad)))
    left, right = [s.replace('_', BLANK) for s in (left.ljust(3, '_'), right.ljust(4, '_'))]
    p = {'spec': spec.strip(), 'left': left, 'right': right, 'text': (left + ' ' + right).rstrip(), 'bg_want': parse_bg(bg, spec)}
    p['wins'] = windows(p)
    return p

def parse_bg(s, spec):
    s = s.strip().lower().replace("jimrob's", 'jr').replace('jimrobs', 'jr').replace('jimrob', 'jr').replace(',', ' ').replace('-', ' ').split()
    if not s or s == ['any']: return None
    if len(s) == 1 and s[0].isdigit() and int(s[0]) < 8: return int(s[0])
    names = ['cougar', 'owl', 'cactus', 'fire']
    if s[0] in names and s[1:] in ([], ['jr']): return names.index(s[0]) + (4 if s[1:] else 0)
    raise SystemExit('%r: background is cougar, owl, cactus or fire, with -jr for the JimRob\'s frame, or 0 to 7' % spec)

def bg_of(a, c):
    """Background from where the groups start: its row is the 3-group's start div 4, its column the 4-group's start div 8."""
    return (a // 4) * 2 + c // 8

def windows(p):
    """Every (A, C) where the plate's two groups agree with each other, and the cells they need, wrapping at 16."""
    out = []
    for a in range(16):
        for c in range(16):
            need = {}
            for start, s in ((a, p['left']), (c, p['right'])):
                for k, ch in enumerate(s):
                    if need.setdefault((start + k) % 16, ch) != ch: break
                else: continue
                break
            else: out.append((a, c, tuple(sorted(need.items()))))
    return out

def solve(items, base):
    """A row 0 holding every plate, as (row, placement per item), or None. items: (plate, background or None).
    Depth first, most constrained plate first, placements sharing the most cells (then changing the fewest shipped ones) first.
    Copies of one text must take different backgrounds, or they'd be the same plate."""
    opts = [[w for w in p['wins'] if bg is None or bg_of(w[0], w[1]) == bg] for p, bg in items]
    if all(bg is None for _, bg in items): opts[0] = [w for w in opts[0] if w[0] == 0]    # nothing pins it: turn the row so plate 1 starts at 0
    order = sorted(range(len(items)), key=lambda i: len(opts[i]))
    row = [None] * 16; pick = [None] * len(items); used = set()
    def go(k):
        if k == len(order): return True
        i = order[k]; text = items[i][0]['text']
        cands = [w for w in opts[i] if (text, bg_of(w[0], w[1])) not in used and all(row[c] in (None, ch) for c, ch in w[2])]
        cands.sort(key=lambda w: (sum(row[c] is None for c, _ in w[2]), sum(row[c] is None and base[c] != ch for c, ch in w[2])))
        for w in cands:
            new = [c for c, ch in w[2] if row[c] is None]
            for c, ch in w[2]: row[c] = ch
            pick[i] = w; used.add((text, bg_of(w[0], w[1])))
            if go(k + 1): return True
            for c in new: row[c] = None
            used.discard((text, bg_of(w[0], w[1])))
        return False
    return (row, pick) if go(0) else None

def pack(plates, base):
    """Plates in the order given, each kept if it fits with those before it; a background that can't be had is dropped, not the plate."""
    kept, refused, notes, layout = [], [], [], ([None] * 16, [])
    for p in plates:
        same = [q for q, _ in kept if q['text'] == p['text']]
        if same and (p['bg_want'] is None or any(q['bg_want'] == p['bg_want'] for q in same)):
            notes.append('%s: already kept' % p['spec']); continue
        tries = [p['bg_want']] + ([None] if p['bg_want'] is not None and not same else [])   # same text, any background: a repeat
        for bg in tries:
            r = solve([(q, b) for q, b in kept] + [(p, bg)], base)
            if r:
                kept.append((p, bg)); layout = r
                break
        else:
            if same: notes.append('%s: no room for that background, and the text is already kept' % p['spec'])
            else: refused.append(p)
    return kept, refused, notes, layout

# ---- seeds: the shader's three sines, in float32 as on the GPU
def shader(seed):
    """seed (float or array) -> glyph row R, 3-group start A, 4-group start C."""
    s = (np.asarray(seed, np.float32) + np.float32(TEST_SEED)).astype(np.float32)
    f = lambda k: 1 + np.sin((s * np.float32(k)).astype(np.float32).astype(np.float64))
    b, a, c = f(K_ROW), f(K_A3), f(K_C4)
    return np.minimum(np.floor(4 * b).astype(int), 7), np.floor(8 * a).astype(int) % 16, np.floor(8 * c).astype(int) % 16

def plate_text(seed, rows):
    R, A, C = [int(x) for x in shader(seed)]
    r = rows[R]
    return R, A, C, ''.join(r[(A + k) % 16] for k in range(3)) + ' ' + ''.join(r[(C + k) % 16] for k in range(4)), bg_of(A, C)

def row0_seeds(lo=-200.0, hi=200.0, step=0.0002):
    """(A, C) -> (seed, width): the middle of the widest run of seeds landing on glyph row 0 with those starts (ties: nearer 0)."""
    seed = np.arange(lo, hi, step, dtype=np.float64).astype(np.float32)
    R, A, C = shader(seed)
    key = np.where(R == 0, A * 16 + C, -1)
    edges = np.flatnonzero(np.diff(key)) + 1
    best = {}
    for st, en in zip(np.r_[0, edges], np.r_[edges, len(key)]):
        k = int(key[st])
        if k < 0: continue
        w = (en - st) * step; mid = float(seed[(st + en - 1) // 2])
        if k not in best or w > best[k][1] + 1e-9 or (abs(w - best[k][1]) < 1e-9 and abs(mid) < abs(best[k][0])): best[k] = (mid, w)
    return {(k // 16, k % 16): v for k, v in best.items()}

# ---- the atlas
def load_atlas():
    t = srtex.open_tex(SOURCE, TEXTURE); h = srtex.parse_cvbm(t.cvbm)
    if t.gvbh is None or t.dir.lower() != GDIR: raise SystemExit('high mips of the atlas not found (looked for %s\\%s)' % (GDIR, GVBH))
    mips = []
    for st, lvl, sl, off, sz, w, hh in srtex.subresources(h):
        if st == 'h': mips.append({'off': off, 'size': sz, 'w': w, 'h': hh, 'img': srtex.decode_surface(h, t.gvbh[off:off + sz], w, hh)})
    if [m['w'] for m in mips] != [512, 256] or h['fname'] != 'BC7': raise SystemExit('atlas is not the BC7 512 + 256 high mips the tool knows')
    return t, h, mips

def cell(img, r, c, lvl):
    w, hh = CW >> lvl, CH >> lvl
    return img[r * hh:(r + 1) * hh, c * w:(c + 1) * w]

def glyph_sources(a0):
    """char -> (row, col): of each character's copies in the atlas, the one most like the others (copies differ by a pixel shift or block noise)."""
    found = collections.defaultdict(list)
    for r, s in enumerate(ROWS):
        for c, ch in enumerate(s): found[ch].append((r, c))
    out = {}
    for ch, at in found.items():
        cs = [cell(a0, r, c, 0).astype(int) for r, c in at]
        out[ch] = at[int(np.argmin([sum(np.abs(x - y).sum() for y in cs) for x in cs]))]
    return out

# ---- GDI text, for letters the atlas lacks and the preview's labels
class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [('biSize', ctypes.c_uint32), ('biWidth', ctypes.c_int32), ('biHeight', ctypes.c_int32), ('biPlanes', ctypes.c_uint16),
                ('biBitCount', ctypes.c_uint16), ('biCompression', ctypes.c_uint32), ('biSizeImage', ctypes.c_uint32), ('biXPelsPerMeter', ctypes.c_int32),
                ('biYPelsPerMeter', ctypes.c_int32), ('biClrUsed', ctypes.c_uint32), ('biClrImportant', ctypes.c_uint32)]

class Gdi:
    """White text on black in a DIB; read back as 0..1."""
    def __init__(s, w=640, h=640):
        g = s.g = ctypes.WinDLL('gdi32'); vp = ctypes.c_void_p
        for name, args, res in (('CreateCompatibleDC', [vp], vp), ('CreateDIBSection', [vp, vp, ctypes.c_uint, ctypes.POINTER(vp), vp, ctypes.c_uint32], vp),
                                ('SelectObject', [vp, vp], vp), ('CreateFontW', [ctypes.c_int] * 5 + [ctypes.c_uint32] * 8 + [ctypes.c_wchar_p], vp),
                                ('SetTextColor', [vp, ctypes.c_uint32], ctypes.c_uint32), ('SetBkMode', [vp, ctypes.c_int], ctypes.c_int),
                                ('TextOutW', [vp, ctypes.c_int, ctypes.c_int, ctypes.c_wchar_p, ctypes.c_int], ctypes.c_int), ('GdiFlush', [], ctypes.c_int),
                                ('DeleteObject', [vp], ctypes.c_int), ('GetTextFaceW', [vp, ctypes.c_int, ctypes.c_wchar_p], ctypes.c_int)):
            f = getattr(g, name); f.argtypes = args; f.restype = res
        s.w, s.h = w, h; s.dc = g.CreateCompatibleDC(None)
        bi = BITMAPINFOHEADER(ctypes.sizeof(BITMAPINFOHEADER), w, -h, 1, 32, 0, 0, 0, 0, 0, 0)
        s.bits = ctypes.c_void_p(); bmp = g.CreateDIBSection(s.dc, ctypes.byref(bi), 0, ctypes.byref(s.bits), None, 0)
        g.SelectObject(s.dc, bmp); g.SetTextColor(s.dc, 0xFFFFFF); g.SetBkMode(s.dc, 1)

    def text(s, txt, face, height, weight=0, quality=3, x=0, y=0):
        """quality 3: no smoothing (for drawing at 4x and shrinking), 4: smoothed. Returns None when Windows lacks the face."""
        g = s.g; font = g.CreateFontW(-height, 0, 0, 0, weight, 0, 0, 0, 1, 0, 0, quality, 0, face)
        old = g.SelectObject(s.dc, font); got = ctypes.create_unicode_buffer(64); g.GetTextFaceW(s.dc, 64, got)
        ctypes.memset(s.bits, 0, s.w * s.h * 4)
        g.TextOutW(s.dc, x, y, txt, len(txt)); g.GdiFlush()
        img = np.frombuffer(ctypes.string_at(s.bits, s.w * s.h * 4), 'u1').reshape(s.h, s.w, 4)[:, :, 1].astype(np.float64) / 255
        g.SelectObject(s.dc, old); g.DeleteObject(font)
        return img if got.value.lower() == face.lower() else None

# ---- drawing letters the atlas lacks: a Windows font fitted to the shipped glyphs
F = 4                                           # drawn at 4x, then shrunk
EM, AT = 280, (160, 120)                        # font size and pen position in the 640x640 DIB
BLUR = 6                                        # high-res pixels; the weight is set by where a blurred glyph is cut
CUTS = np.linspace(0.15, 0.85, 15)
# Bahnschrift is Windows' DIN 1451, the family the plate font looks drawn from. Agency FB scores a little better on the numbers but
# looks squarer next to the shipped O, C and S; --font picks any installed face.
FACES = [('Bahnschrift Condensed', 0), ('Bahnschrift SemiBold Condensed', 0), ('Bahnschrift SemiCondensed', 0), ('Bahnschrift SemiBold SemiConden', 0)]

def ink(img):
    ys, xs = np.nonzero(img > 0.5)
    return (ys.min(), ys.max() + 1, xs.min(), xs.max() + 1) if len(ys) else None

def glyph_box(h_cell):
    """Where the shipped glyphs sit in their cell, in pixels, with edges to a fraction of a pixel (all glyphs fill the same box)."""
    a = h_cell.astype(np.float64) / 255; cols = a.max(0); rows = a.max(1)
    xs = np.flatnonzero(cols > 0.02); ys = np.flatnonzero(rows > 0.02)
    return (ys[0] + 1 - rows[ys[0]], ys[-1] + rows[ys[-1]], xs[0] + 1 - cols[xs[0]], xs[-1] + cols[xs[-1]])

def place(img, src, dst):
    """Area-resize img[src] onto dst (high-res cell pixels, float edges) of an empty high-res cell."""
    y0, y1, x0, x1 = src; by0, by1, bx0, bx1 = dst
    hh, ww = max(1, int(round(by1 - by0))), max(1, int(round(bx1 - bx0)))
    r = srtex._area(img[y0:y1, x0:x1, None], ww, hh)[:, :, 0]
    out = np.zeros((CH * F, CW * F)); oy, ox = int(round(by0)), int(round(bx0))
    ty0, tx0 = max(0, oy), max(0, ox); ty1, tx1 = min(out.shape[0], oy + hh), min(out.shape[1], ox + ww)
    if ty1 > ty0 and tx1 > tx0: out[ty0:ty1, tx0:tx1] = r[ty0 - oy:ty1 - oy, tx0 - ox:tx1 - ox]
    return out

def box_blur(a, r):
    for ax in (0, 1):
        c = np.cumsum(np.pad(a, [(r + 1, r) if k == ax else (0, 0) for k in range(2)]), ax)
        a = (np.take(c, range(2 * r + 1, c.shape[ax]), ax) - np.take(c, range(0, c.shape[ax] - 2 * r - 1), ax)) / (2 * r + 1)
    return a

def shrink(binary):
    return binary.reshape(CH, F, CW, F).mean((1, 3)) * 255

class FontFit:
    """One face, drawn and boxed the way the plate font is: letters and digits stretched to the shared glyph box, other marks scaled as H is."""
    def __init__(s, gdi, face, weight, box):
        s.gdi, s.face, s.weight, s.box = gdi, face, weight, box; s.cache = {}
        s.H = s.render('H')

    def render(s, ch):
        if ch not in s.cache: s.cache[ch] = s.gdi.text(ch, s.face, EM, s.weight, 3, *AT)
        return s.cache[ch]

    def blurred(s, ch):
        img = s.render(ch); own = ink(img)
        if own is None: return np.zeros((CH * F, CW * F))
        by0, by1, bx0, bx1 = [v * F for v in s.box]
        if ch.isalnum() and not ch.islower():   # stretched to the box; Q by its O, so the tail hangs out as it should
            ref = ink(s.render('O')) if ch == 'Q' else own
            sy, sx = (by1 - by0) / (ref[1] - ref[0]), (bx1 - bx0) / (ref[3] - ref[2])
            dst = (by0 + (own[0] - ref[0]) * sy, by0 + (own[1] - ref[0]) * sy, bx0 + (own[2] - ref[2]) * sx, bx0 + (own[3] - ref[2]) * sx)
        else:                                   # H's scale and baseline, centred across the box: lower case and marks
            hb = ink(s.H); sy, sx = (by1 - by0) / (hb[1] - hb[0]), (bx1 - bx0) / (hb[3] - hb[2])
            w = (own[3] - own[2]) * sx; mid = (bx0 + bx1) / 2
            dst = (by0 + (own[0] - hb[0]) * sy, by0 + (own[1] - hb[0]) * sy, mid - w / 2, mid + w / 2)
        return box_blur(place(img, own, dst), BLUR)

    def glyph(s, ch, cut):
        return shrink(s.blurred(ch) > cut)

def fit_font(gdi, a0, srcs, box, only=None):
    """The face and weight whose letters come closest to the shipped ones (mean difference over every shipped character but 1, whose foot no font has)."""
    test = [ch for ch in sorted(srcs) if ch != '1']
    ship = {ch: cell(a0, *srcs[ch], 0).astype(np.float64) for ch in test}
    tried = []
    for face, weight in FACES if only is None else [(only.partition(':')[0], int(only.partition(':')[2] or 0))]:
        if gdi.text('H', face, EM, weight, 3, *AT) is None: continue
        ff = FontFit(gdi, face, weight, box)
        bl = {ch: ff.blurred(ch) for ch in test}
        for cut in CUTS:
            err = float(np.mean([np.abs(shrink(bl[ch] > cut) - ship[ch]).mean() for ch in test]))
            tried.append((err, face, weight, float(cut)))
    if not tried: raise SystemExit('none of the fonts tried is installed' if only is None else 'no font called %r' % only)
    tried.sort()
    err, face, weight, cut = tried[0]
    return FontFit(gdi, face, weight, box), cut, {'face': face, 'weight': weight, 'cut': round(cut, 3), 'mean_error': round(err, 2),
                                                  'others': [(f, round(e, 2)) for e, f, w, c in sorted({(f, w): (e, f, w, c) for e, f, w, c in tried[::-1]}.values())[:6]]}

def letter_i(one, box):
    """I from the shipped 1: its stem, its foot cut to 4 px past the stem, and the foot turned over as a top bar, centred in the box.
    The 1 has a foot, so a plain bar would look thin beside it; this I stays apart from 1, T and L."""
    a = one.astype(np.float64)
    wide = [y for y in range(CH) if (a[y] > 128).sum() > 16]                # the foot's rows
    foot0 = wide[0] - 1; mirror = int(round(box[0] + box[1])) - 1          # row y of the foot becomes row mirror - y at the top
    stem_row = a[mirror // 2]                                               # a row of plain stem, half way down, clear of the flag
    xs = np.flatnonzero(stem_row > 8); sx0, sx1 = xs[0], xs[-1] + 1
    lo, hi = sx0 - 4, sx1 + 4
    out = np.zeros_like(a)
    for y in range(foot0, mirror + 1):
        out[y, lo:hi] = a[y, lo:hi]; out[y, lo] *= 0.5; out[y, hi - 1] *= 0.5   # half-covered bar ends, as an edge would be
        out[mirror - y] = out[y]
    out[mirror - foot0 + 1:foot0, sx0:sx1] = stem_row[sx0:sx1]
    return np.roll(out, int(round((box[2] + box[3]) / 2 - (lo + hi) / 2)), 1)

# ---- BC7: change a block's alpha, keeping its colour bits
def bits(v, pos, n): return (v >> pos) & ((1 << n) - 1)
def setbits(v, pos, n, x): return (v & ~(((1 << n) - 1) << pos)) | ((int(x) & ((1 << n) - 1)) << pos)

def mode_of(b0):
    for m in range(8):
        if b0 >> m & 1: return m
    return 8

def alpha_layout(v, m):
    """Modes with alpha apart from colour, not rotated: (endpoint bit positions, endpoint bits, index start, index bits)."""
    if m == 5 and bits(v, 6, 2) == 0: return (50, 58), 8, 97, 2
    if m == 4 and bits(v, 5, 2) == 0: return ((38, 44), 6, 81, 3) if bits(v, 7, 1) == 0 else ((38, 44), 6, 50, 2)

def expand(e, nb): return e if nb == 8 else (e << (8 - nb)) | (e >> (2 * nb - 8))

def fit_alpha(t, nb, ib):
    """Endpoints and indices for 16 alpha values, the anchor (pixel 0) index kept below half as BC7 needs."""
    t = t.astype(np.int64); top = (1 << nb) - 1; wts = srtex.WT[ib]; R = 4 if nb == 8 else 2
    lo, hi = int(round(t.min() * top / 255)), int(round(t.max() * top / 255))
    E = np.array([(a, b) for a in range(max(0, lo - 1), min(top, lo + R) + 1) for b in range(max(0, hi - R), min(top, hi + 1) + 1)])
    ex = expand(E, nb)
    pal = ((64 - wts)[None, :] * ex[:, :1] + wts[None, :] * ex[:, 1:] + 32) >> 6
    d = (t[None, :, None] - pal[:, None, :]) ** 2
    k = int(d.min(2).sum(1).argmin()); e0, e1 = E[k]; ix = d[k].argmin(1)
    if ix[0] >= 1 << (ib - 1): e0, e1, ix = e1, e0, (1 << ib) - 1 - ix
    return e0, e1, ix

def alpha_only(old, tgt, src=None):
    """A new block with alpha tgt and the old colour bits, or None. src: the block the glyph came from, whose alpha bits are copied when laid out alike."""
    v = int.from_bytes(old, 'little'); m = mode_of(old[0]); lay = alpha_layout(v, m)
    if lay:
        (p0, p1), nb, ip, ib = lay; n = 16 * ib - 1
        if src is not None:
            sv = int.from_bytes(src, 'little')
            if mode_of(src[0]) == m and alpha_layout(sv, m) == lay:
                for pos, k in ((p0, nb), (p1, nb), (ip, n)): v = setbits(v, pos, k, bits(sv, pos, k))
                return v.to_bytes(16, 'little'), 'alpha bits copied'
        e0, e1, ix = fit_alpha(tgt, nb, ib)
        v = setbits(setbits(v, p0, nb, e0), p1, nb, e1); pos = ip
        for i in range(16):
            k = ib - (i == 0); v = setbits(v, pos, k, ix[i]); pos += k
        return v.to_bytes(16, 'little'), 'alpha refitted'
    if (tgt == tgt[0]).all():                   # one alpha for the block: modes 6 and 7 can take it if their p bits allow
        val = int(tgt[0])
        if m == 6 and bits(v, 63, 1) == val & 1 and bits(v, 64, 1) == val & 1:
            v = setbits(setbits(v, 49, 7, val >> 1), 56, 7, val >> 1)
            return v.to_bytes(16, 'little'), 'alpha set'
        x = [x for x in range(64) if expand(x, 6) == val]
        if m == 7 and x and all(bits(v, 94 + e, 1) == x[0] & 1 for e in range(4)):
            for e in range(4): v = setbits(v, 74 + 5 * e, 5, x[0] >> 1)
            return v.to_bytes(16, 'little'), 'alpha set'
    return None, None

def pack45(m, isel, crgb, cix, cib, araw, aix, aib):
    """A mode 4 or 5 block (not rotated) from colour endpoints (2 x 3) and alpha endpoints (2), each with its own indices."""
    cbits, abits = (7, 8) if m == 5 else (5, 6)
    crgb, cix, araw, aix = np.array(crgb), np.array(cix), np.array(araw), np.array(aix)
    if cix[0] >= 1 << (cib - 1): crgb, cix = crgb[::-1], (1 << cib) - 1 - cix
    if aix[0] >= 1 << (aib - 1): araw, aix = araw[::-1], (1 << aib) - 1 - aix
    v = setbits(1 << m, 7, 1, isel) if m == 4 else 1 << m
    for ch in range(3):
        for e in range(2): v = setbits(v, 8 + cbits * (2 * ch + e), cbits, crgb[e][ch])
    for e in range(2): v = setbits(v, (50 if m == 5 else 38) + abits * e, abits, araw[e])
    sets = [(66, cix, cib), (97, aix, aib)] if m == 5 else [(50, cix, cib), (81, aix, aib)] if isel == 0 else [(50, aix, aib), (81, cix, cib)]
    for pos, ix, ib in sets:
        for i in range(16):
            k = ib - (i == 0); v = setbits(v, pos, k, ix[i]); pos += k
    return v.to_bytes(16, 'little')

def reencode(rgb, tgt):
    """The block again, for blocks whose colour and alpha share indices: of srtex's encoder and modes 5 and 4 (colour fitted to the old
    colour, alpha to the new), the one that changes the colour least, alpha error counting a quarter as much."""
    cands = [srtex.bc7_encode(np.concatenate([rgb, tgt[:, None]], 1)[None].astype('u1'))]
    P = rgb[None].astype(np.float32); allm = np.ones((1, 16), bool)
    for m, isel, cb, cib, nb, aib in ((5, 0, 7, 2, 8, 2), (4, 0, 5, 2, 6, 3), (4, 1, 5, 3, 6, 2)):
        r, _, ix, _ = srtex._fit(P, allm, cb, None, srtex.WT[cib])
        e0, e1, aix = fit_alpha(tgt, nb, aib)
        cands.append(pack45(m, isel, r[0], ix[0], cib, (e0, e1), aix, aib))
    dec = srtex.bc7_decode(b''.join(cands)).astype(np.int64)
    score = 4 * ((dec[:, :, :3] - rgb[None]) ** 2).sum((1, 2)) + ((dec[:, :, 3] - tgt[None]) ** 2).sum(1)
    return cands[int(score.argmin())]

def rewrite(data, img, jobs):
    """jobs: block index -> (16 alpha values, source block or None). Blocks whose alpha already matches stay as they are."""
    out = bytearray(data); stats = collections.Counter(); bw = img.shape[1] // 4
    for bi, (tgt, src) in sorted(jobs.items()):
        by, bx = divmod(bi, bw); old = bytes(data[bi * 16:bi * 16 + 16])
        px = img[by * 4:by * 4 + 4, bx * 4:bx * 4 + 4].reshape(16, 4).astype(np.int64)
        if (px[:, 3] == tgt).all(): stats['unchanged'] += 1; continue
        new, how = alpha_only(old, tgt, src)
        if new is None: new, how = reencode(px[:, :3], tgt), 're-encoded'
        out[bi * 16:bi * 16 + 16] = new; stats[how] += 1
    return bytes(out), stats

# ---- the build
def build(plates_in, out, font=None):
    os.makedirs(out, exist_ok=True); work = os.path.join(out, 'work'); os.makedirs(work, exist_ok=True)
    t, h, mips = load_atlas(); a0 = mips[0]['img'][:, :, 3]; a1 = mips[1]['img'][:, :, 3]
    base = list(ROWS[0])
    kept, refused, notes, (row, picks) = pack(plates_in, base)
    srcs = glyph_sources(a0)
    need = sorted({ch for ch in row if ch not in (None, BLANK)} - set(srcs))
    gdi = Gdi(); box = glyph_box(cell(a0, *srcs['H'], 0)); fit = None
    drawn = {}
    for ch in need:
        if ch == 'I': drawn[ch] = letter_i(cell(a0, *srcs['1'], 0), box); continue
        if fit is None: ff, cut, fit = fit_font(gdi, a0, srcs, box, font)
        drawn[ch] = ff.glyph(ch, cut)
        if not drawn[ch].any(): raise SystemExit('%s draws nothing in %s' % (ch, ff.face))
    # Targets: alpha of every row-0 cell that changes, at both mips, and where each copied glyph came from
    jobs = [{}, {}]; final = []
    for c in range(16):
        ch = row[c]
        if ch is None or ch == base[c]: final.append(base[c]); continue
        final.append(ch)
        for lvl, a in ((0, a0), (1, a1)):
            w, hh = CW >> lvl, CH >> lvl; bw = mips[lvl]['w'] // 4
            if ch == BLANK: tgt, src = np.zeros((hh, w)), None
            elif ch in srcs: tgt, src = cell(a, *srcs[ch], lvl).astype(np.float64), srcs[ch]
            else:
                g = drawn[ch]; tgt, src = (g if lvl == 0 else g.reshape(hh, 2, w, 2).mean((1, 3))), None
            tgt = np.clip(np.rint(tgt), 0, 255).astype(np.int64)
            for by in range(hh // 4):
                for bx in range(w // 4):
                    sb = None
                    if src is not None:
                        si = (src[0] * hh // 4 + by) * bw + src[1] * w // 4 + bx
                        sb = t.gvbh[mips[lvl]['off'] + si * 16:mips[lvl]['off'] + si * 16 + 16]
                    jobs[lvl][by * bw + c * w // 4 + bx] = (tgt[by * 4:by * 4 + 4, bx * 4:bx * 4 + 4].reshape(16), sb)
    gvbh = bytearray(t.gvbh); stats = {}
    for lvl, m in enumerate(mips):
        new, st = rewrite(t.gvbh[m['off']:m['off'] + m['size']], m['img'], jobs[lvl])
        gvbh[m['off']:m['off'] + m['size']] = new; stats['mip%d' % lvl] = dict(st)
    gvbh = bytes(gvbh)
    rows = [''.join(final)] + ROWS[1:]
    # Seeds, each checked by running the shader on the number as written
    table = row0_seeds(); placed = []
    for (p, bg), (a, c, cells) in zip(kept, picks):
        seed, width = table[(a, c)]
        txt = '%.4f' % seed
        R, A, C, shown, b = plate_text(float(txt), rows)
        if (R, A, C) != (0, a, c): txt = '%.7f' % seed; R, A, C, shown, b = plate_text(float(txt), rows)
        want = p['left'] + ' ' + p['right']
        placed.append({'text': p['text'], 'spec': p['spec'], 'a': a, 'c': c, 'seed': txt, 'run_width': round(width, 4), 'background': BGS[bg_of(a, c)],
                       'background_wanted': None if p['bg_want'] is None else BGS[p['bg_want']], 'shader_says': shown, 'shader_ok': (R, A, C) == (0, a, c) and shown == want})
    # Files
    pdir = os.path.join(out, 'data', 'sr_boot'); os.makedirs(pdir, exist_ok=True)
    patch = os.path.join(pdir, 'sr_boot_patch.vpp_pc')
    open(patch, 'wb').write(pb.packfile([(GVBH, GDIR, gvbh, None)], flags=0x10000))
    with open(os.path.join(out, 'custom_plates.txt'), 'w', newline='\n') as f:
        for q in placed: f.write('%s|%s|%s\n' % (q['text'], q['seed'], q['background']))
    check = verify(t, h, mips, gvbh, patch, jobs, work)
    preview(os.path.join(out, 'preview.png'), gdi, mips, gvbh, rows, placed, drawn, srcs)
    rep = {'row0_before': ROWS[0], 'row0_after': rows[0].replace(BLANK, '_'), 'plates': placed, 'refused': [p['spec'] for p in refused], 'notes': notes,
           'drawn': sorted(drawn), 'copied_from': {ch: 'row %d col %d' % srcs[ch] for ch in sorted({x for x in row if x in srcs})},
           'font': fit, 'blocks': stats, 'verify': check, 'patch': patch, 'merge_flag': NOTE_MERGE}
    json.dump(rep, open(os.path.join(out, 'report.json'), 'w'), indent=1)
    return rep

def verify(t, h, mips, gvbh, patch, jobs, work):
    """Read the patch back as the game lays it out, export the texture from it with srtex, and compare with the shipped one."""
    b = open(patch, 'rb').read()
    nf, nd, tables, names = struct.unpack_from('<4I', b, 0x10)
    ok_head = b[:4] == pb.MAGIC and struct.unpack_from('<I', b, 4)[0] == 0x11 and struct.unpack_from('<I', b, 0xC)[0] == 0x10000 \
        and tables == nf * 0x30 + nd * 8 and struct.unpack_from('<Q', b, 0x40)[0] == 0x78 + tables + names and struct.unpack_from('<Q', b, 0x20)[0] == len(b)
    (n, d, body, sz, csz), = pb.read_pack(b)
    entry_ok = (n, d, csz, sz, len(body)) == (GVBH, GDIR, -1, len(t.gvbh), len(t.gvbh)) and body == gvbh
    # The texture as files beside each other, exported by srtex as it would any texture, against the shipped export
    vt = os.path.join(work, 'from_patch'); os.makedirs(vt, exist_ok=True); base = t.inner[:-8]
    for ext, raw in (('.cvbm_pc', t.cvbm), ('.gvbm_pc', t.gvbm), ('.gvbh_pc', body)): open(os.path.join(vt, base + ext), 'wb').write(raw)
    srtex.cmd_export(os.path.join(vt, base + '.cvbm_pc'), '-', os.path.join(work, 'export_patch'))
    srtex.cmd_export(SOURCE, TEXTURE, os.path.join(work, 'export_shipped'))
    new = srtex.png_read(os.path.join(work, 'export_patch', base + '.png')); old = srtex.png_read(os.path.join(work, 'export_shipped', base + '.png'))
    rgb = new[:, :, :3] != old[:, :, :3]
    out = {'header_ok': bool(ok_head), 'entry_ok': bool(entry_ok), 'mip0_rgb_pixels_changed': int(rgb.any(2).sum()), 'mip0_rgb_max_change': int(np.abs(new[:, :, :3].astype(int) - old[:, :, :3]).max()),
           'alpha_below_row0_identical': bool((new[CH:, :, 3] == old[CH:, :, 3]).all())}
    for lvl, m in enumerate(mips):
        img = srtex.decode_surface(h, body[m['off']:m['off'] + m['size']], m['w'], m['h']); bw = m['w'] // 4; errs = []
        for bi, (tgt, _) in jobs[lvl].items():
            by, bx = divmod(bi, bw); errs.append(np.abs(img[by * 4:by * 4 + 4, bx * 4:bx * 4 + 4, 3].reshape(16).astype(int) - tgt).max())
        out['mip%d_row0_alpha_max_error' % lvl] = int(max(errs)) if errs else 0
        out['mip%d_rgb_identical' % lvl] = bool((img[:, :, :3] == m['img'][:, :, :3]).all())
        d = np.abs(img[:, :, :3].astype(int) - m['img'][:, :, :3]).max(2)
        out['mip%d_rgb_blocks_changed' % lvl] = int((srtex.to_blocks(d[:, :, None]).max((1, 2)) > 0).sum())
        out['mip%d_rgb_mean_change_in_those' % lvl] = round(float(d[d > 0].mean()), 2) if (d > 0).any() else 0
        out['mip%d_outside_row0_identical' % lvl] = bool((img[CH >> lvl:] == m['img'][CH >> lvl:]).all())
    return out

def preview(path, gdi, mips, gvbh, rows, placed, drawn, srcs):
    """Row 0 as built, the shipped rows under it, the drawn letters between shipped H's, then each plate's text. Glyph alpha as white."""
    m = mips[0]; old = m['img'][:, :, 3]
    a0 = srtex.to_image(srtex.bc7_decode(gvbh[m['off']:m['off'] + m['size']]), m['w'], m['h'], 4)[:, :, 3]
    LW, gap = 230, 6
    lines = [('row 0, built', a0[:CH])] + [('row %d, shipped' % r, old[r * CH:(r + 1) * CH]) for r in range(8)]
    if drawn:
        H = cell(old, *srcs['H'], 0); strip = [H]
        for ch in sorted(drawn): strip += [drawn[ch], H]
        lines.append(('drawn: ' + ' '.join(sorted(drawn)), np.concatenate(strip, 1)))
    for q in placed:
        cs = [cell(a0, 0, (q['a'] + k) % 16, 0) for k in range(3)] + [np.zeros((CH, CW // 2))] + [cell(a0, 0, (q['c'] + k) % 16, 0) for k in range(4)]
        lines.append(('%s   %s   %s' % (q['text'], q['seed'], q['background']), np.concatenate(cs, 1)))
    W = LW + max(l[1].shape[1] for l in lines); out = np.zeros((sum(CH + gap for _ in lines) + gap, W), 'u1'); y = gap
    lab = Gdi(LW, CH)
    for label, a in lines:
        out[y:y + CH, LW:LW + a.shape[1]] = np.clip(a, 0, 255)
        t = lab.text(label, 'Segoe UI', 14, 400, 4, 4, 24)
        if t is not None: out[y:y + CH, :LW] = t * 200
        y += CH + gap
    srtex.png_write(path, np.kron(out, np.ones((2, 2), 'u1')))     # twice the size, to see the edges

def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('plates', nargs='*'); ap.add_argument('--file'); ap.add_argument('--font')
    ap.add_argument('--out', default=os.path.join(tempfile.gettempdir(), 'sr5_plate_maker'))
    ap.add_argument('--install', action='store_true', help='copy the patch and the list into the game folder')
    a = ap.parse_args()
    specs = list(a.plates)
    if a.file:
        for line in open(a.file, encoding='utf-8'):
            line = line.split('#')[0].strip()
            if line: specs.append(line)
    if not specs: raise SystemExit(__doc__)
    rep = build([parse_plate(s) for s in specs], a.out, a.font)
    print('row 0: %s -> %s' % (rep['row0_before'], rep['row0_after']))
    print('%d of %d plates fit' % (len(rep['plates']), len(specs)))
    for q in rep['plates']:
        bg = q['background'] + ('' if q['background_wanted'] in (None, q['background']) else ' (wanted %s, no room)' % q['background_wanted'])
        print('  %-9s seed %-10s %-17s %s' % (q['text'], q['seed'], bg, 'checked' if q['shader_ok'] else 'SHADER GIVES ' + q['shader_says']))
    for s in rep['refused']: print('  refused, no room left in row 0: ' + s)
    for s in rep['notes']: print('  ' + s)
    if rep['drawn']:
        how = (['I from the shipped 1'] if 'I' in rep['drawn'] else []) + (['%s in %s' % ('the rest' if 'I' in rep['drawn'] else 'all', rep['font']['face'])] if rep['font'] else [])
        print('drawn: %s (%s)' % (' '.join(rep['drawn']), ', '.join(how)))
    print('blocks:', json.dumps(rep['blocks'])); print('verify:', json.dumps(rep['verify']))
    print('patch  %s  -> sr5\\data\\sr_boot\\' % rep['patch'])
    print('list   %s  -> TweakMenu\\' % os.path.join(a.out, 'custom_plates.txt'))
    print('look   %s' % os.path.join(a.out, 'preview.png'))
    if a.install:
        import shutil
        game = os.path.dirname(DATA)
        shutil.copyfile(rep['patch'], os.path.join(DATA, 'sr_boot', 'sr_boot_patch.vpp_pc'))
        os.makedirs(os.path.join(game, 'TweakMenu'), exist_ok=True)
        shutil.copyfile(os.path.join(a.out, 'custom_plates.txt'), os.path.join(game, 'TweakMenu', 'custom_plates.txt'))
        print('installed: start the game, then Vehicles > License plates > Custom plate')

if __name__ == '__main__':
    main()
