"""The game as it ships today: a straight port of AtBatScene.render at the `.pitch` beat."""
from engine import *

W, H = 320, 224
PARK, FEET = 'PARK 12', '395 FT'
HUD = 'PARK 12  12 PITCHES'
BALL = (172, 151, 3)
CLOUDS = [  # (x, baseline, [(dx, w, rise)])
    (38, 40, [(0, 24, 3), (3, 17, 6), (7, 9, 9)]),
    (196, 58, [(0, 19, 2), (4, 12, 5), (7, 6, 8)]),
    (262, 33, [(0, 26, 3), (5, 18, 7), (9, 11, 10), (12, 5, 13)]),
]


def treeline(c, body, seed=12, x0=0, x1=W, baseline=96, rise=10):
    g = random.Random(seed)
    x = x0 - 6
    while x < x1:
        w = g.randint(5, 9)
        tall = g.randint(0, 4) == 0
        h = max(3, round(rise * (g.uniform(1.05, 1.35) if tall else g.uniform(0.35, 0.8))))
        c.rect(x, baseline - h, w, h, body)
        c.rect(x + 1, baseline - h - 1, max(1, w - 2), 1, body)
        x += w - 1


def water_tower(c, x, baseline, body, detail):
    c.rect(x - 6, baseline - 17, 12, 7, body)
    c.rect(x - 6, baseline - 18, 12, 1, detail)
    c.rect(x - 5, baseline - 10, 2, 10, body)
    c.rect(x + 3, baseline - 10, 2, 10, body)
    c.rect(x - 5, baseline - 6, 10, 1, body)


def pitcher(c, px, py, frame):
    c.rect(px - 2, py - 12, 5, 8, P['ink'])
    c.rect(px - 2, py - 16, 5, 4, P['skin'])
    c.rect(px - 3, py - 18, 7, 2, P['cap'])
    if frame == 0:
        c.rect(px - 1, py - 4, 2, 4, P['ink'])
    elif frame == 1:
        c.rect(px - 1, py - 4, 3, 4, P['ink'])
        c.rect(px + 2, py - 8, 2, 4, P['ink'])
        c.line(px + 3, py - 12, px + 6, py - 20, P['ink'])
    else:
        c.rect(px - 2, py - 4, 2, 4, P['ink'])
        c.rect(px + 1, py - 4, 2, 4, P['ink'])
        c.line(px + 3, py - 10, px + 7, py - 6, P['ink'])


def batter(c, bx, by, frame):
    c.rect(bx - 8, by - 24, 7, 24, P['ink'])
    c.rect(bx + 3, by - 24, 7, 24, P['ink'])
    c.rect(bx - 9, by - 52, 20, 30, P['ink'])
    c.rect(bx - 6, by - 64, 12, 12, P['skin'])
    c.rect(bx - 8, by - 68, 16, 6, P['cap'])
    c.rect(bx - 8, by - 62, 4, 8, P['cap'])
    if frame == 0:
        c.rect(bx + 8, by - 48, 6, 8, P['ink'])
        c.rect(bx + 12, by - 52, 4, 4, P['skin'])
        c.line(bx + 14, by - 52, bx + 22, by - 84, P['bat'], 3)
    elif frame == 1:
        c.rect(bx + 8, by - 44, 10, 6, P['ink'])
        c.rect(bx + 16, by - 44, 4, 4, P['skin'])
        c.line(bx + 18, by - 42, bx + 62, by - 58, P['bat'], 3)
    else:
        c.rect(bx - 14, by - 40, 8, 6, P['ink'])
        c.rect(bx - 16, by - 40, 4, 4, P['skin'])
        c.line(bx - 16, by - 40, bx - 40, by - 56, P['bat'], 3)


def zone(c, colour):
    zx, zy, zw, zh = 140, 136, 40, 50
    for i in range(0, zw + 1, 3):
        c.px(zx + i, zy, colour); c.px(zx + i, zy + zh, colour)
    for j in range(0, zh + 1, 3):
        c.px(zx, zy + j, colour); c.px(zx + zw, zy + j, colour)


def lamps(c, lit=1, total=3):
    for i in range(total):
        c.rect(166 + i * 5, 85, 3, 3, P['score'] if i < lit else P['ink'])


def flags(c):
    for dx in (6, 55):
        x = 128 + dx
        c.rect(x, 72, 1, 8, P['chalk'])
        for j in range(3):
            c.rect(x + 1, 72 + j, 4 - j, 1, P['cap'])


def scene():
    c = Canvas(W, H)
    c.rect(0, 0, W, H, P['sky1'])
    c.rect(0, 44, W, 26, P['sky2'])
    c.rect(0, 70, W, 26, P['sky3'])
    c.dither(0, 42, W, 4, P['sky1'], P['sky2'])
    c.dither(0, 68, W, 4, P['sky2'], P['sky3'])
    for x, base, blocks in CLOUDS:
        for dx, w, rise in blocks:
            c.rect(x + dx, base - rise, w, rise, P['chalk'])
            c.rect(x + dx, base - 1, w, 1, P['sky3'])
    treeline(c, P['sky2'])
    water_tower(c, 248, 96, P['wall'], P['shade'])
    for x in (40, 280):
        c.rect(x, 96 - 28, 2, 28, P['score'])
    c.rect(0, 96, W, 8, P['wall'])
    c.rect(0, 96, W, 1, P['chalk'])
    c.rect(0, 104, W, H - 104, P['grassA'])
    gy = 104
    while gy < H:
        c.rect(0, gy, W, 6, P['grassB']); gy += 12
    c.rect(128, 80, 64, 16, P['wall'])
    c.rect(128, 80, 64, 1, P['chalk'])
    c.t3(134, 84, FEET, P['score'])
    c.t3(134, 91, PARK, P['chalk'])
    lamps(c)
    flags(c)
    c.line(160, 196, 40, 104, P['chalk'])
    c.line(160, 196, 280, 104, P['chalk'])
    c.rect(148, 116, 24, 5, P['dirt'])
    c.rect(150, 121, 20, 2, P['dirtD'])
    c.rect(120, 184, 80, 14, P['dirt'])
    c.rect(124, 198, 72, 4, P['dirtD'])
    c.rect(152, 190, 16, 4, P['chalk'])
    pitcher(c, 160, 117, 2)
    zone(c, P['chalk'])
    batter(c, 104, 222, 0)
    bx, by, r = BALL
    c.baseball(bx, by, r, P['sky3'])
    c.px(bx + r, by, P['ink'])
    c.t3(8, H - 12, '87 MPH', P['chalk'])
    c.t3(8, 8, HUD, P['chalk'])
    return c


def batter_sprite(frame):
    s = Sprite(128, 100, 50, 97)
    batter(s, 50, 97, frame)
    return s


def pitcher_sprite(frame):
    s = Sprite(40, 40, 16, 36)
    pitcher(s, 16, 36, frame)
    return s
