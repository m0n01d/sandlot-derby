"""A tiny software pixel canvas mirroring App/Sources/PixelCanvas.swift, plus shape/shading
helpers for the design variants. No AA, no alpha: a pixel is a colour or it is not there."""
import zlib, struct, math, random

GRID = (0x00, 0x22, 0x44, 0x66, 0x88, 0xAA, 0xCC, 0xEE)
LEGACY = {'#116633', '#221144', '#EEDD22'}   # docs/palette.md entries that sit off the 8-level grid


def col(h):
    h = h.upper()
    r, g, b = int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16)
    if h not in LEGACY:
        assert all(c in GRID for c in (r, g, b)), 'off the Genesis grid: ' + h
    return (r, g, b)


def hexof(c):
    return '#%02X%02X%02X' % c


# docs/palette.md
P = {k: col(v) for k, v in dict(
    sky1='#4466CC', sky2='#66AAEE', sky3='#AACCEE', grassA='#22AA44', grassB='#228844',
    wall='#226644', dirt='#CC8844', dirtD='#AA6622', chalk='#EEEEEE', ink='#222244',
    skin='#EEAA88', cap='#CC2222', bat='#AA8844', score='#EEDD22', shade='#116633',
    night='#221144').items()}

F3 = {
    "0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111",
    "4": "101101111001001", "5": "111100111001111", "6": "111100111101111", "7": "111001001001001",
    "8": "111101111101111", "9": "111101111001111", "F": "111100110100100", "T": "111010010010010",
    "H": "101101111101101", "R": "110101110101101", "P": "110101110100100", "A": "010101111101101",
    "K": "101110100110101", "M": "101111111101101", "D": "110101101101110", "E": "111100111100111",
    "G": "111100101101111", "S": "111100111001111", "I": "111010010010111", "N": "110101101101101",
    "W": "101101101111101", "L": "100100100100111", "O": "111101101101111", "U": "101101101101111",
    "C": "111100100100111", "B": "110101110101110", "V": "101101101101010", "Y": "101101010010010",
    " ": "000000000000000", "J": "001001001101111", "Q": "111101101111001", "X": "101101010101101",
    "Z": "111001010100111", ".": "000000000000010", ":": "000010000010000", "-": "000000111000000",
    "%": "101001010100101", "/": "001001010100100", ",": "000000000010100", "·": "000000010000000",
}


class Canvas:
    def __init__(s, w, h, bg=None):
        s.w, s.h = w, h
        s.p = [[bg] * w for _ in range(h)]

    def set(s, x, y, c):
        if 0 <= x < s.w and 0 <= y < s.h:
            s.p[y][x] = c

    def get(s, x, y):
        if 0 <= x < s.w and 0 <= y < s.h:
            return s.p[y][x]
        return None

    # --- the Swift primitives, same truncation semantics -------------------------------
    def px(s, x, y, c):
        s.set(int(x), int(y), c)

    def rect(s, x, y, w, h, c):
        x0, y0 = max(0, int(x)), max(0, int(y))
        x1, y1 = min(s.w, int(x) + int(w)), min(s.h, int(y) + int(h))
        for j in range(y0, y1):
            for i in range(x0, x1):
                s.p[j][i] = c

    def line(s, x0, y0, x1, y1, c, t=1):
        x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
        dx, sx = abs(x1 - x0), (1 if x0 < x1 else -1)
        dy, sy = -abs(y1 - y0), (1 if y0 < y1 else -1)
        err = dx + dy
        t = max(1, t)
        while True:
            for i in range(t):
                for j in range(t):
                    s.set(x0 + i - (t >> 1), y0 + j - (t >> 1), c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy; x0 += sx
            if e2 <= dx:
                err += dx; y0 += sy

    def disc(s, cx, cy, r, c):
        if r <= 0:
            return
        cxi, cyi, ri = int(cx), int(cy), max(0, int(r))
        r2 = r * r + r * 0.5
        for y in range(-ri, ri + 1):
            for x in range(-ri, ri + 1):
                if x * x + y * y <= r2:
                    s.set(cxi + x, cyi + y, c)

    def dither(s, x, y, w, h, a, b):
        x0, y0 = int(x), int(y)
        for j in range(int(h)):
            for i in range(int(w)):
                s.set(x0 + i, y0 + j, a if ((i + j) & 1) else b)

    def ring(s, cx, cy, r, c, gap=3):
        n = max(8, int(round(2 * math.pi * r / gap)))
        for i in range(n):
            a = 2 * math.pi * i / n
            s.px(cx + math.cos(a) * r, cy + math.sin(a) * r, c)

    def t3(s, x, y, text, c, scale=1, shadow=None):
        if shadow is not None:
            s.t3(x + scale, y + scale, text, shadow, scale)
        cx = x
        for ch in text.upper():
            bits = F3.get(ch, F3[" "])
            for j in range(5):
                for i in range(3):
                    if bits[j * 3 + i] == "1":
                        s.rect(cx + i * scale, y + j * scale, scale, scale, c)
            cx += 4 * scale

    def baseball(s, cx, cy, r, highlight, outline=None):
        if outline is not None and r >= 2:
            s.disc(cx, cy, r + 1, outline)
        s.disc(cx, cy, r, P['chalk'])
        x, y = math.floor(cx), math.floor(cy)
        seam = {0: [], 1: [], 2: [(1, 0)], 3: [(1, -1), (2, 0), (1, 1)]}.get(
            int(r), [(1, -2), (2, -1), (2, 0), (2, 1), (1, 2)])
        for dx, dy in seam:
            s.px(x + dx, y + dy, P['cap'])
        if r >= 3:
            s.px(x - 1, y - 1, highlight)

    # --- extras for the variants ---------------------------------------------------------
    def blit(s, o, x, y):
        for j in range(o.h):
            row = o.p[j]
            for i in range(o.w):
                if row[i] is not None:
                    s.set(x + i, y + j, row[i])

    def stamp(s, rows, legend, x, y):
        """ASCII sprite: one char per pixel, '.' is nothing."""
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                if ch != '.' and ch != ' ':
                    s.set(x + i, y + j, legend[ch])

    def ellipse(s, cx, cy, rx, ry, c):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1:
                    s.set(x, y, c)

    def used(s):
        out = {}
        for row in s.p:
            for c in row:
                if c is not None:
                    out[c] = out.get(c, 0) + 1
        return out

    def crop(s, x0, y0, x1, y1):
        o = Canvas(x1 - x0, y1 - y0)
        for j in range(o.h):
            for i in range(o.w):
                o.p[j][i] = s.get(x0 + i, y0 + j)
        return o

    def png(s, path, scale=1):
        W, H = s.w * scale, s.h * scale
        raw = bytearray()
        for row in s.p:
            line = bytearray()
            for c in row:
                px = bytes((c[0], c[1], c[2], 255)) if c is not None else b'\0\0\0\0'
                line += px * scale
            for _ in range(scale):
                raw += b'\0' + line

        def chunk(tag, data):
            body = tag + data
            return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body) & 0xffffffff)
        with open(path, 'wb') as f:
            f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 6, 0, 0, 0))
                    + chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b''))


# --- masks with a fake surface normal, for cylinder/sphere shading ---------------------------

def m_ellipse(cx, cy, rx, ry):
    out = []
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            nx, ny = (x + .5 - cx) / rx, (y + .5 - cy) / ry
            if nx * nx + ny * ny <= 1:
                out.append((x, y, nx, ny))
    return out


def m_capsule(x0, y0, r0, x1, y1, r1):
    out = []
    dx, dy = x1 - x0, y1 - y0
    L2 = dx * dx + dy * dy or 1e-9
    R = max(r0, r1) + 1
    for y in range(int(min(y0, y1) - R) - 1, int(max(y0, y1) + R) + 2):
        for x in range(int(min(x0, x1) - R) - 1, int(max(x0, x1) + R) + 2):
            px_, py_ = x + .5, y + .5
            u = max(0, min(1, ((px_ - x0) * dx + (py_ - y0) * dy) / L2))
            qx, qy = x0 + dx * u, y0 + dy * u
            r = r0 + (r1 - r0) * u
            ex, ey = px_ - qx, py_ - qy
            if ex * ex + ey * ey <= r * r:
                out.append((x, y, ex / r, ey / r))
    return out


def m_poly(pts):
    ys = [p[1] for p in pts]
    rows = {}
    for y in range(int(min(ys)) - 1, int(max(ys)) + 2):
        yc = y + .5
        xs = []
        for i in range(len(pts)):
            (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
            if (ay <= yc < by) or (by <= yc < ay):
                xs.append(ax + (yc - ay) / (by - ay) * (bx - ax))
        xs.sort()
        for k in range(0, len(xs) - 1, 2):
            for x in range(int(math.floor(xs[k] - .5)), int(math.ceil(xs[k + 1] + .5))):
                if xs[k] <= x + .5 <= xs[k + 1]:
                    rows.setdefault(y, []).append(x)
    out = []
    y_lo, y_hi = min(rows), max(rows)
    for y, xr in rows.items():
        lo, hi = min(xr), max(xr)
        mid, half = (lo + hi) / 2, max(1, (hi - lo) / 2)
        for x in xr:
            ny = -0.35 if y - y_lo < 2 else (0.35 if y_hi - y < 2 else 0)
            out.append((x, y, (x - mid) / half * 0.95, ny))
    return out


class Sprite(Canvas):
    """A transparent canvas whose parts are shaded by one light and (optionally) outlined."""

    def __init__(s, w, h, ox, oy, light=(-0.6, -0.8), cuts=(0.35, -0.3), inner=False):
        super().__init__(w, h)
        s.ox, s.oy = ox, oy            # where sprite-local (0, 0) — the feet — sits
        n = math.hypot(*light)
        s.light = (light[0] / n, light[1] / n)
        s.cuts = cuts                  # l above cuts[0] is light, below cuts[1] is dark
        s.inner = inner                # draw each part's own darker contour over what is below it

    def part(s, mask, ramp, line=None):
        """ramp: one colour (flat) or [dark, mid, light(, rim)]."""
        pts = [(x + s.ox, y + s.oy, nx, ny) for x, y, nx, ny in mask]
        if s.inner and line is not None:
            inside = {(x, y) for x, y, _, _ in pts}
            for x, y in inside:
                for ax, ay in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    q = (x + ax, y + ay)
                    if q not in inside and s.get(*q) is not None:
                        s.set(q[0], q[1], line)
        for x, y, nx, ny in pts:
            if not isinstance(ramp, list):
                s.set(x, y, ramp); continue
            l = nx * s.light[0] + ny * s.light[1]
            if len(ramp) == 4 and l > 0.72:
                c = ramp[3]
            elif l > s.cuts[0]:
                c = ramp[2]
            elif l < s.cuts[1]:
                c = ramp[0]
            else:
                c = ramp[1]
            s.set(x, y, c)

    def lstamp(s, rows, legend, x, y):
        s.stamp(rows, legend, x + s.ox, y + s.oy)

    def lset(s, x, y, c):
        s.set(x + s.ox, y + s.oy, c)

    def outline(s, c, diagonal=False):
        nb = [(1, 0), (-1, 0), (0, 1), (0, -1)] + ([(1, 1), (-1, 1), (1, -1), (-1, -1)] if diagonal else [])
        edge = []
        for y in range(s.h):
            for x in range(s.w):
                if s.p[y][x] is None and any(s.get(x + a, y + b) is not None for a, b in nb):
                    edge.append((x, y))
        for x, y in edge:
            s.p[y][x] = c

    def bounds(s):
        xs = [x for y in range(s.h) for x in range(s.w) if s.p[y][x] is not None]
        ys = [y for y in range(s.h) for x in range(s.w) if s.p[y][x] is not None]
        return min(xs), min(ys), max(xs) + 1, max(ys) + 1

    def trimmed(s, pad=1):
        x0, y0, x1, y1 = s.bounds()
        return s.crop(max(0, x0 - pad), max(0, y0 - pad), min(s.w, x1 + pad), min(s.h, y1 + pad))


BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def bayer_gradient(c, x, y, w, h, a, b):
    """Ordered-dither blend from a (top) to b (bottom) across h rows."""
    for j in range(int(h)):
        t = (j + .5) / h
        for i in range(int(w)):
            c.set(int(x) + i, int(y) + j, b if t > (BAYER[(int(y) + j) % 4][(int(x) + i) % 4] + .5) / 16 else a)
