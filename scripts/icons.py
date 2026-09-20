#!/usr/bin/env python3
"""Draw the app-icon candidates as 64x64 pixel art and scale them 16x to 1024.

Everything here obeys the game's own rules (CLAUDE.md, docs/palette.md): one
palette line, no alpha, no gradients, no anti-aliasing, dither only in the sky,
and an integer scale to the shipped size. Re-run to regenerate docs/icons/.

    python3 scripts/icons.py            # writes docs/icons/*.png
"""

import os
import struct
import zlib

GRID = 64          # the icon's design space, in the spirit of 320x224
SCALE = 16         # 64 * 16 = 1024, the App Store size, nearest-neighbour

# --- docs/palette.md, verbatim -------------------------------------------------
P = {
    "sky1": (0x44, 0x66, 0xCC), "sky2": (0x66, 0xAA, 0xEE), "sky3": (0xAA, 0xCC, 0xEE),
    "grassA": (0x22, 0xAA, 0x44), "grassB": (0x22, 0x88, 0x44), "wall": (0x22, 0x66, 0x44),
    "dirt": (0xCC, 0x88, 0x44), "dirtD": (0xAA, 0x66, 0x22), "chalk": (0xEE, 0xEE, 0xEE),
    "ink": (0x22, 0x22, 0x44), "skin": (0xEE, 0xAA, 0x88), "cap": (0xCC, 0x22, 0x22),
    "bat": (0xAA, 0x88, 0x44), "score": (0xEE, 0xDD, 0x22), "shade": (0x11, 0x66, 0x33),
    "night": (0x22, 0x11, 0x44), "nightSky3": (0x44, 0x66, 0x88),
}


class Pix:
    """The prototype's px/rect/line/disc/dither, on a flat RGB buffer."""

    def __init__(self, w, h, fill="sky1"):
        self.w, self.h = w, h
        self.buf = [P[fill]] * (w * h)

    def px(self, x, y, c):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.buf[y * self.w + x] = P[c]

    def rect(self, x, y, w, h, c):
        for j in range(int(h)):
            for i in range(int(w)):
                self.px(x + i, y + j, c)

    def line(self, x0, y0, x1, y1, c, t=1):
        x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        half = t >> 1
        while True:
            for j in range(t):
                for i in range(t):
                    self.px(x0 + i - half, y0 + j - half, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def disc(self, cx, cy, r, c):
        for y in range(-r, r + 1):
            for x in range(-r, r + 1):
                if x * x + y * y <= r * r + r * 0.5:
                    self.px(cx + x, cy + y, c)

    def ring(self, cx, cy, r, c, t=1):
        """The outline of a disc: every pixel in the disc but not the inner one."""
        for y in range(-r, r + 1):
            for x in range(-r, r + 1):
                d = x * x + y * y
                inner = r - t
                if d <= r * r + r * 0.5 and d > inner * inner + inner * 0.5:
                    self.px(cx + x, cy + y, c)

    def dither(self, x, y, w, h, a, b):
        for j in range(h):
            for i in range(w):
                self.px(x + i, y + j, a if (i + j) & 1 else b)


# --- type: the game's own two faces -------------------------------------------
F3 = {
    "0": "111101101101111", "1": "010110010010111", "2": "111001111100111",
    "3": "111001111001111", "4": "101101111001001", "5": "111100111001111",
    "6": "111100111101111", "7": "111001001001001", "8": "111101111101111",
    "9": "111101111001111", "A": "010101111101101", "B": "110101110101110",
    "C": "011100100100011", "D": "110101101101110", "E": "111100110100111",
    "F": "111100110100100", "G": "011100101101011", "H": "101101111101101",
    "I": "111010010010111", "J": "001001001101010", "K": "101110100110101",
    "L": "100100100100111", "M": "101111111101101", "N": "101111111111101",
    "O": "010101101101010", "P": "110101110100100", "R": "110101110101101",
    "S": "011100010001110", "T": "111010010010010", "U": "101101101101011",
    "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
    "Y": "101101010010010", "Z": "111001010100111", " ": "000000000000000",
    ".": "000000000000010", "·": "000000010000000", "-": "000000111000000",
}
F5 = {
    "0": "01110100011000110001100011000101110",
    "1": "00100011000010000100001000010001110",
    "2": "01110100010000100010001000100011111",
    "3": "11111000100010000010000011000101110",
    "4": "00010001100101010010111110001000010",
    "5": "11111100001111000001000011000101110",
    "6": "00110010001000011110100011000101110",
    "7": "11111000010001000100010000100001000",
    "8": "01110100011000101110100011000101110",
    "9": "01110100011000101111000010001001100",
    "D": "11110100011000110001100011000111110",
    "E": "11111100001000011110100001000011111",
    "H": "10001100011000111111100011000110001",
    "R": "11110100011000111110101001001010001",
    "S": "01111100001000001110000010000111110",
    "Y": "10001100010101000100001000010000100",
    " ": "00000000000000000000000000000000000",
}


def text3(p, x, y, s, c, scale=1):
    for ch in s.upper():
        m = F3.get(ch, F3[" "])
        for j in range(5):
            for i in range(3):
                if m[j * 3 + i] == "1":
                    p.rect(x + i * scale, y + j * scale, scale, scale, c)
        x += 4 * scale
    return x


def text5(p, x, y, s, c, scale=1):
    for ch in s.upper():
        m = F5.get(ch, F5[" "])
        for j in range(7):
            for i in range(5):
                if m[j * 5 + i] == "1":
                    p.rect(x + i * scale, y + j * scale, scale, scale, c)
        x += 6 * scale
    return x


def text3_width(s, scale=1):
    return len(s) * 4 * scale - scale


def text5_width(s, scale=1):
    return len(s) * 6 * scale - scale


# --- shared pieces -------------------------------------------------------------
def sky(p, night=False, top=0, bottom=GRID):
    """Three bands with one four-row dither per transition, per docs/palette.md."""
    s1, s2, s3 = ("night", "ink", "nightSky3") if night else ("sky1", "sky2", "sky3")
    h = bottom - top
    b1 = top + int(h * 0.34)
    b2 = top + int(h * 0.66)
    p.rect(0, top, GRID, b1 - top, s1)
    p.rect(0, b1, GRID, b2 - b1, s2)
    p.rect(0, b2, GRID, bottom - b2, s3)
    p.dither(0, b1 - 2, GRID, 4, s1, s2)
    p.dither(0, b2 - 2, GRID, 4, s2, s3)


def stars(p, count, height):
    for i in range(count):
        p.px((i * 53 + 17) % GRID, (i * 31 + 5) % height, "chalk")


def grass(p, y):
    p.rect(0, y, GRID, GRID - y, "grassA")
    for j in range(y + 2, GRID, 4):
        p.rect(0, j, GRID, 2, "grassB")


def baseball(p, cx, cy, r, seam="cap"):
    """A chalk disc with the two classic seams. No shading — chalk has one job.

    Each seam is an arc whose horizontal distance from centre grows toward the
    poles, so the pair bows *toward* each other (`) (`), which is what reads as
    a baseball. Stitch ticks only appear once the ball is big enough to hold them.
    """
    p.disc(cx, cy, r, "chalk")
    span = max(1, int(round(r * 0.80)))
    for t in range(-span, span + 1):
        k = t / span
        d = int(round(r * 0.44 + r * 0.26 * k * k))
        p.px(cx - d, cy + t, seam)
        p.px(cx + d, cy + t, seam)
        if r >= 10 and t % max(3, r // 4) == 0 and abs(t) < span - 1:
            p.rect(cx - d + 1, cy + t, 2, 1, seam)
            p.rect(cx + d - 2, cy + t, 2, 1, seam)


def batter_contact(p, x, ground, s=1.0):
    """The contact frame from prototypes/02-mood-board.html, at any size.

    `s` scales the prototype's 48-tall cell so an icon can crop as close as it
    likes; the proportions and the three-to-five colours on the character are
    the sprite's, unchanged.
    """
    def u(n):
        return int(round(n * s))

    p.rect(x - u(9), ground - u(14), u(5), u(14), "ink")      # back leg
    p.rect(x + u(4), ground - u(14), u(5), u(14), "ink")      # front leg
    p.rect(x - u(4), ground - u(14), u(8), u(4), "ink")       # crouch
    p.rect(x - u(5), ground - u(30), u(11), u(17), "ink")     # torso
    hx = x + u(2)
    p.rect(hx - u(4), ground - u(40), u(8), u(10), "skin")    # face
    p.rect(hx - u(5), ground - u(42), u(9), u(4), "cap")      # cap crown
    p.rect(hx - u(5), ground - u(38), u(11), u(2), "cap")     # brim, points right
    p.rect(hx - u(4), ground - u(36), u(2), u(6), "ink")      # hair edge
    p.rect(x + u(3), ground - u(27), u(8), u(4), "ink")       # arms
    p.rect(x + u(10), ground - u(27), u(3), u(3), "skin")     # hands
    tipx, tipy = x + u(30), ground - u(24)
    p.line(x + u(11), ground - u(26), tipx, tipy, "bat", max(2, u(2)))
    return tipx, tipy


# --- the five candidates -------------------------------------------------------
# Every one keeps its subject inside the corner mask (`rounded()` below shows
# exactly what iOS cuts) and is built to survive the 60 px home-screen size.

def icon_contact():
    """01 CONTACT — the hero beat, cropped close: silhouette, ball, the slash.

    Champion Baseball's trick, stolen from the mood board: a baseball game may
    cut to a portrait for the moment of contact. So this one does not show the
    field, it shows the swing.
    """
    p = Pix(GRID, GRID)
    sky(p, bottom=50)
    grass(p, 50)
    tipx, tipy = batter_contact(p, 16, 54, s=1.15)
    bx, by = tipx + 4, tipy - 1
    p.line(bx - 16, by + 14, bx + 8, by - 7, "score", 4)      # the slash, through the ball
    baseball(p, bx, by, 6)
    return p


def icon_ball():
    """02 THE BALL — one object, the biggest read there is, trail for motion."""
    p = Pix(GRID, GRID)
    sky(p, bottom=54)
    grass(p, 54)
    for i in range(5):                                        # the every-fourth-frame trail
        t = i / 4
        p.disc(int(4 + t * 12), int(52 - t * 10), 1 + i // 2, "chalk")
    baseball(p, 35, 27, 19)
    return p


def icon_over_the_wall():
    """03 OVER THE WALL — the whole game as one shape: the arc clearing the fence.

    The wall is on screen from the first frame, so the goal is never explained
    (mood board, constraint two). An icon can do the same job.
    """
    p = Pix(GRID, GRID)
    sky(p, bottom=46)
    grass(p, 46)
    p.rect(34, 24, GRID - 34, 22, "wall")                     # the fence, right of frame
    p.rect(34, 24, GRID - 34, 2, "score")                      # its scoreboard rail
    p.rect(34, 26, 1, 20, "ink")                               # the near edge, so it pops
    p.rect(34, 45, GRID - 34, 1, "shade")                      # where it meets the grass
    for i in range(11):                                        # the arc, as trail dots
        t = i / 10
        ax = int(6 + t * 38)
        ay = int(52 - (58 * t - 46 * t * t))
        p.disc(ax, ay, 2 if i < 8 else 1, "chalk")
    baseball(p, 52, 13, 8)
    return p


def icon_slash():
    """04 THE SLASH — the one gesture as a mark. Night ground, nothing else.

    The slice is the only input the game ever asks for; this is that input,
    drawn at icon size, with the ball frozen at the crossing.
    """
    p = Pix(GRID, GRID, "night")
    stars(p, 30, GRID)
    for i in range(46):                                       # a tapering slice trail
        t = i / 45
        sx = int(8 + t * 48)
        sy = int(54 - t * 44)
        w = int(round(7 - 5 * t))
        p.rect(sx - w // 2 - 1, sy - w // 2 - 1, w + 2, w + 2, "chalk")
    for i in range(46):
        t = i / 45
        sx = int(8 + t * 48)
        sy = int(54 - t * 44)
        w = max(1, int(round(6 - 4.5 * t)))
        p.rect(sx - w // 2, sy - w // 2, w, w, "score")
    baseball(p, 30, 32, 10)
    p.ring(30, 32, 14, "score", 1)                            # the contact ring
    return p


def icon_night_scoreboard():
    """05 NIGHT GAME — the outfield scoreboard read: yellow on wall green.

    Night parks swap three sky colours and nothing else, so this is the same
    icon as the others wearing the palette's one legal variation.
    """
    p = Pix(GRID, GRID, "night")
    sky(p, night=True, bottom=38)
    stars(p, 22, 22)
    for tx in (10, 50):                                       # the light towers
        p.rect(tx, 10, 4, 12, "ink")
        p.rect(tx - 3, 6, 10, 4, "score")
        p.rect(tx - 2, 5, 8, 1, "chalk")
    p.rect(0, 34, GRID, 22, "wall")                           # the scoreboard face
    p.rect(0, 33, GRID, 1, "score")                            # its rail
    grass(p, 56)
    w = text5_width("HR", 3)
    text5(p, (GRID - w) // 2, 37, "HR", "score", 3)
    baseball(p, 45, 24, 6)
    for i in range(6):
        p.disc(int(35 - i * 5), int(27 + i * 2), 1, "chalk")
    return p


CANDIDATES = [
    ("01-contact", "CONTACT", icon_contact),
    ("02-the-ball", "THE BALL", icon_ball),
    ("03-over-the-wall", "OVER THE WALL", icon_over_the_wall),
    ("04-the-slash", "THE SLASH", icon_slash),
    ("05-night-game", "NIGHT GAME", icon_night_scoreboard),
]


# --- PNG out (stdlib only) -----------------------------------------------------
def write_png(path, buf, w, h):
    raw = b"".join(
        b"\x00" + b"".join(bytes(buf[y * w + x]) for x in range(w)) for y in range(h)
    )

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as f:
        f.write(png)


def upscale(p, scale):
    w, h = p.w * scale, p.h * scale
    out = [None] * (w * h)
    for y in range(h):
        row = (y // scale) * p.w
        for x in range(w):
            out[y * w + x] = p.buf[row + x // scale]
    return out, w, h


def rounded(buf, w, h, bg):
    """iOS masks the corners; the sheet shows what the home screen shows."""
    r = int(w * 0.2237)
    for y in range(h):
        for x in range(w):
            cx = r if x < r else (w - 1 - r if x > w - 1 - r else x)
            cy = r if y < r else (h - 1 - r if y > h - 1 - r else y)
            if (x - cx) ** 2 + (y - cy) ** 2 > r * r:
                buf[y * w + x] = bg
    return buf


def blit(dst, dw, src, sw, sh, ox, oy):
    for y in range(sh):
        for x in range(sw):
            dst[(oy + y) * dw + ox + x] = src[y * sw + x]


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(here, "docs", "icons")
    os.makedirs(out, exist_ok=True)

    icons = []
    for slug, label, fn in CANDIDATES:
        p = fn()
        buf, w, h = upscale(p, SCALE)
        write_png(os.path.join(out, f"{slug}-1024.png"), buf, w, h)
        icons.append((slug, label, p))
        print(f"docs/icons/{slug}-1024.png")

    # Contact sheet: each candidate at 256, 120 and 60 — the sizes that decide it.
    sizes = [256, 120, 60]
    pad, row_h, left = 28, 300, 28
    sheet_w = left + sum(s + 32 for s in sizes) + 460
    sheet_h = pad + row_h * len(icons)
    paper = (0xF2, 0xF0, 0xE8)
    sheet = [paper] * (sheet_w * sheet_h)
    for idx, (slug, label, p) in enumerate(icons):
        y0 = pad + idx * row_h
        x = left
        for s in sizes:
            k = s // GRID if s % GRID == 0 else None
            if k:
                buf, w, h = upscale(p, k)
            else:  # nearest-neighbour to a non-multiple, for the true home-screen size
                w = h = s
                buf = [p.buf[(y * GRID // s) * GRID + (x2 * GRID // s)]
                       for y in range(s) for x2 in range(s)]
            buf = rounded(buf, w, h, paper)
            blit(sheet, sheet_w, buf, w, h, x, y0 + (sizes[0] - s) // 2)
            x += s + 32
        lp = Pix(1, 1)  # a scratch surface so text3 can draw into the sheet
        lw = text3_width(label, 3)
        tile = Pix(lw + 2, 20, "chalk")
        text3(tile, 0, 0, label, "ink", 3)
        tbuf, tw, th = upscale(tile, 2)
        for yy in range(th):
            for xx in range(tw):
                c = tbuf[yy * tw + xx]
                if c != P["chalk"]:
                    sheet[(y0 + 18 + yy) * sheet_w + x + 12 + xx] = c
        sub = f"{idx + 1} OF 5"
        stile = Pix(text3_width(sub, 2) + 2, 12, "chalk")
        text3(stile, 0, 0, sub, "ink", 2)
        sbuf, stw, sth = upscale(stile, 2)
        for yy in range(sth):
            for xx in range(stw):
                c = sbuf[yy * stw + xx]
                if c != P["chalk"]:
                    sheet[(y0 + 70 + yy) * sheet_w + x + 12 + xx] = c
    write_png(os.path.join(out, "contact-sheet.png"), sheet, sheet_w, sheet_h)
    print("docs/icons/contact-sheet.png")


if __name__ == "__main__":
    main()
