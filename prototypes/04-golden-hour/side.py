"""The flight camera (WideScene): today's frame ported, then the three variants, each in the
wide and the close framing. python3 side.py [now a b c]"""
import os, sys, json
from engine import *
import now as NOW
from variants import B, C, INK, OUT, round_cloud, puffy_cloud, hills, speckle, streak

W, H = 320, 224
WALL, WALL_H, TOP, DEPTH, STEPS, FLAGS = 395.0, 14.0, 60.0, 150.0, 6, 3
BOARD = dict(back=35.0, bottom=49.0, w=28.0, h=14.0)


# --- DerbyCore, ported: the flight and the framing -------------------------------------------

def simulate(ev_mph=108.0, angle=29.0):
    k, cd, cl, g, dt, ft = 0.0174, 0.33, 0.15, 9.81, 1 / 240, 3.28084
    v = ev_mph * 0.44704
    vx, vy = v * math.cos(math.radians(angle)), v * math.sin(math.radians(angle))
    x, y, pts, apex = 0.0, 1.0, [], 0.0
    while y >= 0:
        s = math.hypot(vx, vy)
        ax, ay = -k * cd * s * vx - k * cl * s * vy, -g - k * cd * s * vy + k * cl * s * vx
        vx += ax * dt; vy += ay * dt; x += vx * dt; y += vy * dt
        pts.append((x * ft, max(0, y * ft)))
        apex = max(apex, y * ft)
    return pts, pts[-1][0], apex


PTS, DIST, APEX = simulate()


class Frame:
    def __init__(s, cam, ball_ft=0.0):
        park = W * (2 / 3) / (WALL + 24)
        if cam == 'wide':
            s.scale = min(park, W / (DIST + 20 + 24), (176 - 16) / max(1, APEX))
            s.ox, s.ground = 24 * s.scale, 176.0
        else:
            s.scale = min(park * 2, W * 0.45 / (DIST - WALL + 20))
            s.ox = W * 0.55 - WALL * s.scale
            s.ground = 176.0 + max(0, 24 - (176 - ball_ft * s.scale))
        s.cam = cam

    def x(s, f): return s.ox + f * s.scale
    def y(s, f): return s.ground - f * s.scale


def stands_h(feet):
    back = feet - WALL
    if back < 0:
        return 0.0
    if back >= DEPTH:
        return TOP
    return WALL_H + (TOP - WALL_H) * (math.floor(back / DEPTH * STEPS) + 1) / STEPS


def ball_index(cam):
    target = 250 if cam == 'wide' else 370
    return next(i for i, p in enumerate(PTS) if p[0] >= target)


def hud(c, fr, i, shadow=None):
    c.t3(8, 8, '108 MPH', P['score'], 2, shadow)
    c.t3(8, 20, '29 DEG', P['score'], 2, shadow)
    c.t3(8, 34, 'FASTBALL', P['chalk'], 1, shadow)
    bx, by = fr.x(PTS[i][0]), fr.y(PTS[i][1]) - 3
    c.t3(min(W - 30, bx + 6), max(6, by - 10), '%d FT' % round(PTS[i][0]), P['chalk'], 1, shadow)
    c.t3(W - 10 - len(NOW.PARK) * 4, H - 12, NOW.PARK, P['chalk'], 1, shadow)


# ======================================================================================
# NOW — WideScene.render + BackdropArt.sideBackdrop/crowd/standsFlags, as shipped
# ======================================================================================

NOW_CLOUDS = [(84, 52, [(0, 22, 3), (3, 15, 6), (7, 8, 9)]), (150, 26, [(0, 26, 2), (5, 17, 5), (9, 9, 8)]),
              (236, 44, [(0, 18, 3), (4, 11, 6)])]


def now_batter(c, x, y, scale, frame=2):
    bx, by = math.floor(x), y
    h = max(6.0, round(6.5 * scale))
    w = max(3, round(h / 3))
    legs, torso = max(1, round(h * 0.33)), max(1, round(h * 0.38))
    head = max(2, h - legs - torso); cap_rows = max(1, round(head / 3))
    left, leg_w = bx - math.floor(w / 2), max(1, math.floor(w / 3))
    sh = by - legs - torso
    c.rect(left, by - legs, leg_w, legs, P['ink']); c.rect(left + w - leg_w, by - legs, leg_w, legs, P['ink'])
    c.rect(left, sh, w, torso, P['ink']); c.rect(left, sh - head, w, head, P['skin'])
    c.rect(left, sh - head, w + 1, cap_rows, P['cap'])
    hy = sh + round(torso * 0.4)
    c.line(left, hy, left - h * 0.5, by - h * 1.15, P['bat'], 2 if h >= 16 else 1)


def now_side(cam):
    i = ball_index(cam)
    fr = Frame(cam, PTS[i][1])
    g0 = fr.ground
    c = Canvas(W, H)
    c.rect(0, 0, W, H, P['sky1']); c.rect(0, 70, W, 60, P['sky2']); c.rect(0, 130, W, max(0, g0 - 130), P['sky3'])
    c.dither(0, 66, W, 8, P['sky1'], P['sky2']); c.dither(0, 126, W, 8, P['sky2'], P['sky3'])
    for x, base, blocks in NOW_CLOUDS:
        for dx, w, rise in blocks:
            c.rect(x + dx, base - rise, w, rise, P['chalk']); c.rect(x + dx, base - 1, w, 1, P['sky3'])
    wall_x, wall_top, top_y = fr.x(WALL), fr.y(WALL_H), fr.y(TOP)
    # behind: the far piece (upper deck) and the landmark (pennants), on the stands' top
    base, rise = top_y + 1, 13
    deck = round(rise * 0.6)
    c.rect(wall_x, base - rise, W - wall_x, deck, P['wall'])
    ry = base - rise + 2
    while ry < base - rise + deck:
        c.rect(wall_x, ry, W - wall_x, 1, P['sky2']); ry += 3
    c.rect(wall_x, base - rise + deck, W - wall_x, 1, P['wall'])
    cx = wall_x + 6
    while cx < W:
        c.rect(cx, base - rise + deck, 2, rise - deck, P['wall']); cx += 17
    if W - wall_x > 60:
        px_ = wall_x + (W - wall_x) * 0.62
        y0 = base - 15
        c.line(px_ - 24, y0, px_ + 24, y0 + 2, P['wall'])
        t = -22
        while t <= 22:
            ly = y0 + (t + 24) / 48 * 2
            for j in range(4):
                c.rect(px_ + t, ly + j + 1, 4 - j, 1, P['shade'])
            t += 8
    # field
    c.rect(0, g0, W, H - g0, P['grassA'])
    stripe = max(4, round(16 * fr.scale))
    gx = math.fmod(fr.x(0), stripe * 2) - stripe * 2
    while gx < W:
        c.rect(gx, g0, stripe, H - g0, P['grassB']); gx += stripe * 2
    wall_h = WALL_H * fr.scale
    c.rect(wall_x, g0 - wall_h, W - wall_x, wall_h, P['wall'])
    c.rect(wall_x, g0 - wall_h, W - wall_x, 1, P['chalk'])
    c.rect(wall_x, g0 - wall_h - 1, 2, wall_h + 1, P['chalk'])
    f, tick = 100, max(1, round(fr.scale / 0.75))
    while fr.x(f) < W:
        c.rect(fr.x(f), g0, tick, 4 * tick, P['chalk']); f += 100
    c.rect(fr.x(-6), g0, 12 * fr.scale, 3, P['dirt'])
    now_batter(c, fr.x(0), g0, fr.scale)
    # trail and ball
    k = 0
    while k < i:
        c.px(fr.x(PTS[k][0]), fr.y(PTS[k][1]) - 2, P['chalk']); k += 4 if cam == 'close' else 8
    X, Y = fr.x(PTS[i][0]), fr.y(PTS[i][1]) - 3
    if cam == 'wide':
        c.rect(X - 1, Y - 1, 4, 4, P['chalk']); c.px(X, Y, P['sky3']); c.px(X + 1, Y + 1, P['cap'])
    else:
        c.rect(X - 3, g0 + 1, 6, 2, P['shade']); c.baseball(X, Y, 3, P['sky3'])
    # in front of the ball: stands, pole, board, crowd, flags
    c.rect(wall_x, wall_top, W - wall_x, g0 - wall_top, P['wall'])
    c.rect(wall_x, wall_top, W - wall_x, 1, P['chalk'])
    c.rect(wall_x, wall_top - 1, 2, g0 - wall_top + 1, P['chalk'])
    for s_ in range(STEPS):
        f0, f1 = WALL + DEPTH * s_ / STEPS, WALL + DEPTH * (s_ + 1) / STEPS
        hh = WALL_H + (TOP - WALL_H) * (s_ + 1) / STEPS
        x0, x1, top = fr.x(f0), fr.x(f1), fr.y(hh)
        c.rect(x0, top, max(1, x1 - x0), wall_top - top, P['ink']); c.rect(x0, top, max(1, x1 - x0), 1, P['wall'])
    back_x = fr.x(WALL + DEPTH)
    if back_x < W:
        c.rect(back_x, top_y, W - back_x, wall_top - top_y, P['ink']); c.rect(back_x, top_y, W - back_x, 1, P['wall'])
    pole_h = 30 * fr.scale
    c.rect(wall_x, wall_top - pole_h, max(1, round(fr.scale * 1.5)), pole_h, P['score'])
    bl, br = fr.x(WALL + BOARD['back'] - BOARD['w'] / 2), fr.x(WALL + BOARD['back'] + BOARD['w'] / 2)
    bt, bb = fr.y(BOARD['bottom'] + BOARD['h']), fr.y(BOARD['bottom'])
    for lx in (bl + 6 * fr.scale, br - 6 * fr.scale - 2):
        c.rect(lx, bb, 2, 176 - bb, P['ink'])
    c.rect(bl, bt, br - bl, bb - bt, P['ink']); c.rect(bl, bt, br - bl, 1, P['wall'])
    row = bt + 3
    while row < bb - 2:
        dx = bl + 2
        while dx < br - 2:
            c.rect(dx, row, 2, 1, P['chalk']); dx += 4
        row += 4
    c.rect(fr.x(WALL + BOARD['back'] - BOARD['w'] / 2 + 1), fr.y(BOARD['bottom'] + BOARD['h'] - 1),
           max(2, 6 * fr.scale), max(2, 5 * fr.scale), P['score'])
    g = random.Random(12)
    left = max(0, wall_x)
    for _ in range(int((W - left) * max(0, wall_top - top_y) / 13)):
        px_ = g.uniform(left, W)
        seat_top = g0 - stands_h((px_ - fr.ox) / fr.scale) * fr.scale
        if wall_top - seat_top <= 2:
            continue
        py_ = g.uniform(seat_top + 1, wall_top)
        roll = g.random()
        c.px(math.floor(px_), math.floor(py_), P['skin'] if roll < .45 else (P['chalk'] if roll < .8 else P['cap']))
    for n in range(FLAGS):
        fx = round(wall_x + (W - wall_x) * (n + 1) / (FLAGS + 1))
        c.rect(fx, top_y - 9, 1, 9, P['chalk'])
        for j, (dx, w) in enumerate([(0, 5), (0, 5), (1, 4)]):
            c.rect(fx + 1 + dx, top_y - 9 + j, w, 1, P['cap'])
    label_y = g0 - wall_h + 3 if wall_h >= 11 else g0 - wall_h - 8
    c.rect(wall_x + 5, label_y - 1, 13, 7, P['ink']); c.t3(wall_x + 6, label_y, '395', P['score'])
    hud(c, fr, i)
    return c


# ======================================================================================
# Shared by the variants: a field with landmarks, a crowd that sits in rows
# ======================================================================================

def checker_mow(c, fr, a, b, bands=(9, 16, 23)):
    stripe = max(4, round(16 * fr.scale))
    y = fr.ground
    for n, h in enumerate(bands):
        for yy in range(int(y), int(min(H, y + h))):
            for x in range(W):
                k = math.floor((x - fr.x(0)) / stripe)
                c.set(x, yy, a if (k + n) % 2 else b)
        y += h


def lens(c, fr, f0, f1, depth, body, lip=None, light=None):
    """A patch of dirt seen almost edge-on: flat on the far side, rounded toward the camera."""
    x0, x1, g0 = fr.x(f0), fr.x(f1), fr.ground
    cx, rx = (x0 + x1) / 2, max(2, (x1 - x0) / 2)
    for px_, py_, nx, ny in m_ellipse(cx, g0, rx, depth):
        if py_ >= g0:
            tone = body
            if lip is not None and ny > 0.62:
                tone = lip
            elif light is not None and ny < 0.3 and nx < -0.2:
                tone = light
            c.set(px_, py_, tone)


def field_marks(c, fr, dirt, lip, light=None, base=None, shadow=None):
    d = 3 if fr.cam == 'wide' else 5
    lens(c, fr, -14, 16, d + 1, dirt, lip, light)                 # the plate circle
    lens(c, fr, 51, 69, d - 1, dirt, lip, light)                  # the mound
    lens(c, fr, 108, 156, d + 1, dirt, lip, light)                # the infield skin, through second
    c.rect(fr.x(127) - 1, fr.ground, 3 if fr.cam == 'close' else 2, 2, base or P['chalk'])
    c.rect(fr.x(WALL - 16), fr.ground, 16 * fr.scale, d, dirt)     # the warning track
    c.rect(fr.x(WALL - 16), fr.ground + d, 16 * fr.scale, 1, lip)
    f = 100
    while f < WALL - 20:
        x = fr.x(f)
        c.rect(x, fr.ground + 1, 1, 8, P['chalk'])
        c.t3(x + 3, fr.ground + 11, str(f), P['chalk'], 1, shadow)
        f += 100


def crowd_rows(c, fr, seed, heads, shirts, aisle=None, presence=0.86):
    g = random.Random(seed)
    big = fr.cam == 'close'
    pitch_y, pitch_x = (5, 3) if big else (3, 2)
    wall_top = fr.y(WALL_H)
    row, y = 0, wall_top - (3 if big else 2)
    while y > fr.y(TOP) + 1:
        x = fr.x(WALL) + 2 + (row % 2) * (pitch_x // 2 + (1 if big else 0))
        while x < W:
            feet = (x - fr.ox) / fr.scale
            seat_top = fr.y(stands_h(feet))
            on_aisle = (feet - WALL) % 30 < (2.4 if big else 3.2)
            if y - (3 if big else 1) > seat_top:
                if on_aisle:
                    if aisle is not None:
                        c.rect(x, y - (2 if big else 1), 2 if big else 1, pitch_y, aisle)
                elif g.random() < presence:
                    hd, sh = g.choice(heads), g.choice(shirts)
                    if big:
                        c.rect(x, y - 3, 2, 2, hd); c.rect(x, y - 1, 2, 2, sh)
                    else:
                        c.px(x, y - 1, hd); c.px(x, y, sh)
            x += pitch_x
        y -= pitch_y; row += 1


def tiers(c, fr, mass, lip, under=None, edge=None):
    wall_top, top_y = fr.y(WALL_H), fr.y(TOP)
    for s_ in range(STEPS):
        f0, f1 = WALL + DEPTH * s_ / STEPS, WALL + DEPTH * (s_ + 1) / STEPS
        hh = WALL_H + (TOP - WALL_H) * (s_ + 1) / STEPS
        x0, x1, top = fr.x(f0), fr.x(f1), fr.y(hh)
        c.rect(x0, top, max(1, x1 - x0) + 1, wall_top - top, mass)
        c.rect(x0, top, max(1, x1 - x0) + 1, 1, lip)
        if under is not None:
            c.rect(x0, top + 1, max(1, x1 - x0) + 1, 1, under)
        if edge is not None:
            prev = fr.y(WALL_H + (TOP - WALL_H) * s_ / STEPS) if s_ else wall_top
            c.rect(x0, top, 1, prev - top, edge)
    back_x = fr.x(WALL + DEPTH)
    if back_x < W:
        c.rect(back_x, top_y, W - back_x, wall_top - top_y, mass); c.rect(back_x, top_y, W - back_x, 1, lip)
        if under is not None:
            c.rect(back_x, top_y + 1, W - back_x, 1, under)


def foul_pole(c, fr, lit, dark, mesh):
    wall_x, wall_top = fr.x(WALL), fr.y(WALL_H)
    ph, pw = 30 * fr.scale, max(2, round(fr.scale * 2))
    wing = max(3, round(5 * fr.scale))
    for yy in range(int(wall_top - ph), int(wall_top - ph * 0.35)):
        for xx in range(int(wall_x + pw), int(wall_x + pw + wing)):
            if (xx + yy) % 2 == 0:
                c.set(xx, yy, mesh)
    c.rect(wall_x, wall_top - ph, pw, ph, lit)
    c.rect(wall_x + pw - 1, wall_top - ph, 1, ph, dark)
    c.rect(wall_x - 1, wall_top - ph - 1, pw + 2, 1, lit)


def board_box(fr):
    return (round(fr.x(WALL + BOARD['back'] - BOARD['w'] / 2)), round(fr.y(BOARD['bottom'] + BOARD['h'])),
            round(fr.x(WALL + BOARD['back'] + BOARD['w'] / 2)), round(fr.y(BOARD['bottom'])))


def board(c, fr, legs, frame, face, dash, pane, lip=None, glow=None):
    bl, bt, br, bb = board_box(fr)
    big = fr.cam == 'close'
    for lx in (bl + round(6 * fr.scale), br - round(6 * fr.scale) - 2):
        c.rect(lx, bb, 2, fr.y(stands_h(WALL + BOARD['back'])) - bb, legs)
    c.line(bl + round(6 * fr.scale), bb, br - round(6 * fr.scale) - 1, bb + (br - bl) * 0.4, legs)
    c.rect(bl - 1, bt - 1, br - bl + 2, bb - bt + 2, frame)
    c.rect(bl, bt, br - bl, bb - bt, face)
    if lip is not None:
        c.rect(bl - 1, bt - 1, br - bl + 2, 1, lip)
    row = bt + (3 if big else 2)
    while row < bb - 1:
        dx = bl + 2
        while dx < br - 2:
            c.rect(dx, row, 2, 1, dash[(row // 3) % len(dash)]); dx += 4
        row += 4 if big else 3
    pw, ph = max(2, round(6 * fr.scale)), max(2, round(5 * fr.scale))
    if glow is not None:
        c.rect(bl, bt, pw + 2, ph + 2, glow)
    c.rect(bl + 1, bt + 1, pw, ph, pane)


def flags(c, fr, pole, cloth, under, knob=None):
    top_y, wall_x = fr.y(TOP), fr.x(WALL)
    big = fr.cam == 'close'
    ph, fw, fh = (16, 9, 6) if big else (11, 6, 4)
    for n in range(FLAGS):
        fx = round(wall_x + (W - wall_x) * (n + 1) / (FLAGS + 1))
        c.rect(fx, top_y - ph, 1, ph, pole)
        if knob is not None:
            c.rect(fx - 1, top_y - ph - 1, 3, 2, knob)
        for j in range(fh):
            c.rect(fx + 1, top_y - ph + j + 1, max(2, fw - (j * fw) // (fh + 1)), 1, cloth if j < fh - 2 else under)


def upper_deck(c, fr, mass, roof, hole, column, glow=None, outline=None):
    wall_x, base = fr.x(WALL), fr.y(TOP) + 1
    rise = 13 if fr.cam == 'wide' else 24
    deck = round(rise * 0.58)
    x0 = wall_x + 18 * fr.scale
    if outline is not None:
        c.rect(x0 - 3, base - rise - 2, W - x0 + 3, 1, outline)
    c.rect(x0 - 2, base - rise - 1, W - x0 + 2, 2, roof)
    c.rect(x0, base - rise + 1, W - x0, deck - 1, mass)
    ry = base - rise + 3
    while ry < base - rise + deck - 1:
        wx = x0 + 2
        while wx < W:
            lit = glow is not None and (int(wx) * 7 + int(ry)) % 5 < 2
            c.rect(wx, ry, 3 if fr.cam == 'close' else 2, 1, glow if lit else hole)
            wx += 5 if fr.cam == 'close' else 4
        ry += 3
    cx = x0 + 4
    while cx < W:
        c.rect(cx, base - rise + deck, 2, rise - deck, column); cx += 17 if fr.cam == 'wide' else 26


def pennant_string(c, fr, line, cloths):
    wall_x, base = fr.x(WALL), fr.y(TOP) + 1
    rise = 13 if fr.cam == 'wide' else 24
    px_, y0 = wall_x + (W - wall_x) * 0.62, base - rise - (9 if fr.cam == 'wide' else 14)
    c.line(px_ - 30, y0, px_ + 30, y0 + 3, line)
    t, n = -28, 0
    while t <= 26:
        ly = y0 + (t + 30) / 60 * 3
        for j in range(4):
            c.rect(px_ + t, ly + j + 1, 4 - j, 1, cloths[n % len(cloths)])
        t += 7; n += 1
    c.rect(px_ - 31, y0 - 1, 1, base - rise - y0, line); c.rect(px_ + 30, y0 + 2, 1, base - rise - y0 - 3, line)


def trail(c, fr, i, tones, cam):
    """Newest first: big dots near the ball, thinning and cooling with age. No alpha anywhere."""
    step = 4 if cam == 'close' else 8
    n, k = 0, i - step
    while k > 0:
        x, y = fr.x(PTS[k][0]), fr.y(PTS[k][1]) - 2
        if n < 6:
            c.rect(x, y, 2, 2, tones[0])
        elif n < 30 or n % 2 == 0:
            c.px(x, y, tones[1])
        k -= step; n += 1


TINY_A = ["B...RR.", ".B..RRR", "..B.SS.", "..KKKK.", "...KKK.", "...KKK.", "...K.K.", "..KK.KK"]
TINY_B = ["w....KKKK..", ".w..KRRRRK.", "..w.KRHRRRK", "...wKSSEKK.", "..KWWWWK...", "..KWWWWK...",
          "...KRKRK...", "..KKK.KKK.."]


# ======================================================================================
# A — SAME SIXTEEN
# ======================================================================================

def a_side(cam):
    i = ball_index(cam)
    fr = Frame(cam, PTS[i][1]); g0 = fr.ground
    c = Canvas(W, H)
    c.rect(0, 0, W, H, P['sky1']); c.rect(0, 70, W, 60, P['sky2']); c.rect(0, 130, W, max(0, g0 - 130), P['sky3'])
    c.dither(0, 66, W, 8, P['sky1'], P['sky2']); c.dither(0, 126, W, 8, P['sky2'], P['sky3'])
    for x, base, bumps in [(80, 54, [(4, 5), (12, 9), (23, 7), (31, 4)]), (146, 27, [(3, 4), (11, 7), (21, 6), (29, 3)]),
                           (232, 46, [(3, 4), (10, 6), (18, 4)])]:
        round_cloud(c, x, base, bumps, P['chalk'], P['sky3'])
    # the far side of the park: a treeline where the sky used to run straight into the grass
    g = random.Random(4)
    x = -6
    while x < fr.x(WALL):
        w = g.randint(5, 9); h = g.choice((4, 5, 6, 6, 7, 9, 11))
        c.rect(x, g0 - h + w / 2, w, h, P['sky2']); c.ellipse(x + w / 2, g0 - h + w / 2, w / 2 + .5, w / 2 + .5, P['sky2'])
        x += w - 1
    upper_deck(c, fr, P['wall'], P['wall'], P['sky2'], P['wall'])
    pennant_string(c, fr, P['wall'], [P['shade']])
    checker_mow(c, fr, P['grassA'], P['grassB'])
    field_marks(c, fr, P['dirt'], P['dirtD'])
    ts = Canvas(7, 8); ts.stamp(TINY_A, {'B': P['bat'], 'R': P['cap'], 'S': P['skin'], 'K': P['ink']}, 0, 0)
    c.blit(ts, int(fr.x(0)) - 4, int(g0) - 8)
    trail(c, fr, i, [P['chalk'], P['chalk']], cam)
    X, Y = fr.x(PTS[i][0]), fr.y(PTS[i][1]) - 3
    if cam == 'wide':
        c.rect(X - 1, g0 + 2, 4, 1, P['shade'])
        c.rect(X - 1, Y - 1, 4, 4, P['chalk']); c.px(X, Y, P['sky3']); c.px(X + 1, Y + 1, P['cap'])
    else:
        c.rect(X - 3, g0 + 1, 6, 2, P['shade']); c.baseball(X, Y, 3, P['sky3'])
    # in front of the ball
    wall_x, wall_top = fr.x(WALL), fr.y(WALL_H)
    c.rect(wall_x, wall_top, W - wall_x, g0 - wall_top, P['wall'])
    f = WALL + 20
    while fr.x(f) < W:
        c.rect(fr.x(f), wall_top + 1, 1, g0 - wall_top - 1, P['shade']); f += 20
    c.rect(wall_x, g0 - 1, W - wall_x, 1, P['shade'])
    c.rect(wall_x, wall_top, W - wall_x, 1, P['chalk'])
    c.rect(wall_x, wall_top - 1, 2, g0 - wall_top + 1, P['chalk'])
    tiers(c, fr, P['ink'], P['wall'])
    crowd_rows(c, fr, 12, [P['skin']], [P['chalk'], P['chalk'], P['cap']])
    foul_pole(c, fr, P['score'], P['score'], P['score'])
    board(c, fr, P['ink'], P['ink'], P['ink'], [P['chalk']], P['score'], lip=P['wall'])
    flags(c, fr, P['chalk'], P['cap'], P['cap'])
    wall_h = WALL_H * fr.scale
    ly = g0 - wall_h + 3 if wall_h >= 11 else g0 - wall_h - 8
    c.rect(wall_x + 5, ly - 1, 13, 7, P['ink']); c.t3(wall_x + 6, ly, '395', P['score'])
    hud(c, fr, i)
    return c


# ======================================================================================
# B — TWO LINES
# ======================================================================================

def leafy(c, x0, x1, baseline, seed, tones, light=(-0.6, -0.8), radii=(4, 5, 5, 6, 7)):
    g = random.Random(seed)
    items, x = [], x0 - 4
    while x < x1:
        items.append((x, baseline - g.randint(2, 7), g.choice(radii))); x += g.randint(5, 9)
    g.shuffle(items)
    for x, cy, rad in items:
        for px_, py_, nx, ny in m_ellipse(x, cy, rad, rad):
            if py_ < baseline:
                l = nx * light[0] + ny * light[1]
                c.set(px_, py_, tones[2] if l > 0.45 else (tones[0] if l < -0.2 else tones[1]))


def b_side(cam):
    i = ball_index(cam)
    fr = Frame(cam, PTS[i][1]); g0 = fr.ground
    c = Canvas(W, H)
    c.rect(0, 0, W, H, P['sky1']); c.rect(0, 70, W, 60, P['sky2']); c.rect(0, 130, W, max(0, g0 - 130), P['sky3'])
    c.dither(0, 66, W, 8, P['sky1'], P['sky2']); c.dither(0, 126, W, 8, P['sky2'], P['sky3'])
    for x, base, bumps in [(76, 58, [(5, 6), (15, 11), (28, 9), (39, 5)]), (138, 28, [(4, 5), (13, 9), (25, 7), (34, 4)]),
                           (226, 50, [(4, 5), (12, 8), (22, 5)])]:
        puffy_cloud(c, x, base, bumps)
    hills(c, B['haze'], 30, 5, baseline=g0, r=(34, 60))
    hills(c, B['hill'], 17, 9, baseline=g0, r=(20, 34), crest=B['wallL'])
    leafy(c, fr.x(34), fr.x(WALL), g0, 21, [P['shade'], P['grassB'], B['grassL']])
    upper_deck(c, fr, B['shoeL'], B['whiteD'], P['sky2'], B['shoe'], outline=INK)
    pennant_string(c, fr, INK, [B['red'], P['score'], B['white']])
    checker_mow(c, fr, P['grassA'], P['grassB'])
    g = random.Random(7)
    for _ in range(150):
        x, y = g.randint(0, W - 4), int(g0 + 8 + (H - g0 - 8) * g.random())
        here = c.get(x, y)
        if here in (P['grassA'], P['grassB']) and c.get(x + 2, y) == here:
            tone = B['grassL'] if g.random() < .6 else P['shade']
            c.set(x, y, tone); c.set(x + 1, y - 1, tone); c.set(x + 2, y, tone)
    field_marks(c, fr, P['dirt'], P['dirtD'], B['dirtL'], shadow=INK)
    ts = Canvas(11, 8); ts.stamp(TINY_B, {'w': B['wood'], 'K': INK, 'R': B['red'], 'H': B['redL'], 'S': B['skin'],
                                          'E': INK, 'W': B['white']}, 0, 0)
    c.rect(fr.x(0) - 5, g0 + 1, 10, 1, P['dirtD'])
    c.blit(ts, int(fr.x(0)) - 7, int(g0) - 8)
    trail(c, fr, i, [P['chalk'], P['chalk']], cam)
    X, Y = fr.x(PTS[i][0]), fr.y(PTS[i][1]) - 3
    r = 2 if cam == 'wide' else 3
    c.ellipse(X + 1, g0 + 3, r + 2, 1.4, P['shade'])
    c.baseball(X + (1 if cam == 'wide' else 0), Y + (1 if cam == 'wide' else 0), r, P['sky3'], outline=INK)
    # in front of the ball: plank wall, concrete tiers, a crowd in colour
    wall_x, wall_top = fr.x(WALL), fr.y(WALL_H)
    c.rect(wall_x, wall_top, W - wall_x, g0 - wall_top, P['wall'])
    c.rect(wall_x, wall_top + 1, W - wall_x, 1, B['wallL'])
    f = WALL + 10
    while fr.x(f) < W:
        c.rect(fr.x(f), wall_top + 2, 1, g0 - wall_top - 2, P['shade']); f += 10
    c.rect(wall_x, g0 - 1, W - wall_x, 1, B['wallD'])
    c.rect(wall_x, wall_top, W - wall_x, 1, P['score'])
    c.rect(wall_x - 1, wall_top - 1, 3, g0 - wall_top + 1, INK); c.rect(wall_x, wall_top - 1, 1, g0 - wall_top, B['wallL'])
    tiers(c, fr, B['shoe'], B['whiteD'], under=B['shoeL'], edge=INK)
    crowd_rows(c, fr, 12, [B['skin'], B['skin'], B['skinL'], B['skinD'], B['woodD']],
               [B['red'], B['white'], P['sky1'], P['score'], B['grassL'], B['redL'], B['white']], aisle=B['shoeL'])
    foul_pole(c, fr, B['poleL'], B['poleD'], P['score'])
    board(c, fr, INK, INK, B['wallD'], [P['chalk'], P['score']], P['score'], lip=B['wallL'], glow=B['poleL'])
    flags(c, fr, B['white'], B['red'], B['redD'], knob=P['score'])
    wall_h = WALL_H * fr.scale
    ly = g0 - wall_h + 3 if wall_h >= 11 else g0 - wall_h - 9
    c.rect(wall_x + 4, ly - 2, 15, 9, INK); c.rect(wall_x + 5, ly - 1, 13, 7, B['wallD']); c.t3(wall_x + 6, ly, '395', P['score'])
    hud(c, fr, i, shadow=INK)
    return c


# ======================================================================================
# C — GOLDEN HOUR. The sun is low behind the plate, so the stands take it full in the face.
# ======================================================================================

CX = {k: col(v) for k, v in dict(grassSun='#66AA44', crowdA='#CC8888', crowdB='#EECC88', deck='#664466').items()}


def c_side(cam):
    i = ball_index(cam)
    fr = Frame(cam, PTS[i][1]); g0 = fr.ground
    c = Canvas(W, H)
    stops = [(0, 's0'), (12, 's0'), (40, 's1'), (50, 's1'), (78, 's2'), (86, 's2'), (108, 's3'), (114, 's3'),
             (132, 's4'), (138, 's4'), (152, 's5'), (157, 's5'), (168, 's6'), (int(g0), 's6')]
    for (y0, a), (y1, b) in zip(stops, stops[1:]):
        if y1 <= y0:
            continue
        if a == b:
            c.rect(0, y0, W, y1 - y0, C[a])
        else:
            bayer_gradient(c, 0, y0, W, y1 - y0, C[a], C[b])
    sx, sy = 58, g0 - 27
    for y in range(int(sy - 34), int(g0)):
        for x in range(0, 110):
            d = math.hypot(x + .5 - sx, (y + .5 - sy) * 1.2)
            if d <= 11:
                c.set(x, y, C['sun'])
            elif d < 34 and (34 - d) / 23 > (BAYER[y % 4][x % 4] + .5) / 16:
                c.set(x, y, C['s6'])
    for x, y, rx, ry in ((120, 30, 40, 3.2), (158, 37, 24, 2), (250, 58, 46, 3.6), (286, 66, 22, 2), (40, 70, 30, 2.6),
                         (204, 96, 34, 2.6)):
        streak(c, x, y, rx, ry)
    hills(c, C['far'], 30, 5, baseline=g0, r=(34, 60))
    hills(c, C['mid'], 17, 9, baseline=g0, r=(20, 34))
    g = random.Random(21)
    items, x = [], -4
    while x < fr.x(WALL):
        items.append((x, g0 - g.randint(2, 7), g.choice((4, 5, 5, 6, 7)))); x += g.randint(5, 9)
    g.shuffle(items)
    for x, cy, rad in items:
        for px_, py_, nx, ny in m_ellipse(x, cy, rad, rad):
            if py_ < g0:
                l = nx * -0.85 + ny * -0.5
                c.set(px_, py_, C['treeRim'] if l > 0.8 else (P['wall'] if l > 0.15 else C['treeD']))
    upper_deck(c, fr, CX['deck'], C['s6'], C['greyDD'], C['greyDD'], glow=C['sun'])
    pennant_string(c, fr, C['greyDD'], [C['red'], C['s6']])
    checker_mow(c, fr, P['grassA'], P['grassB'])
    # the low sun rakes the far edge of the grass: an ordered-dither wash, brightest by the plate
    for yy in range(int(g0), int(g0) + 9):
        for x in range(W):
            t = max(0, 1 - x / (W * 0.8)) * (1 - (yy - g0) / 9)
            if t > (BAYER[yy % 4][x % 4] + .5) / 16:
                c.set(x, yy, CX['grassSun'])
    field_marks(c, fr, P['dirt'], P['dirtD'], C['dirtL'], shadow=INK)
    ts = Canvas(7, 8); ts.stamp(TINY_A, {'B': C['wood'], 'R': C['red'], 'S': C['skin'], 'K': C['grey']}, 0, 0)
    for k in range(1, 22):                                    # his shadow, long, away from the sun
        if k < 12 or k % 2 == 0:
            c.px(fr.x(0) + k, g0 + 1 + k // 8, P['shade'])
    c.blit(ts, int(fr.x(0)) - 4, int(g0) - 8)
    trail(c, fr, i, [C['sun'], P['chalk']], cam)
    X, Y = fr.x(PTS[i][0]), fr.y(PTS[i][1]) - 3
    if cam == 'wide':
        c.rect(X + 1, g0 + 2, 5, 1, P['shade'])
        c.rect(X - 1, Y - 1, 4, 4, P['chalk']); c.px(X - 1, Y - 1, C['poleL']); c.px(X + 2, Y + 2, C['greyL']); c.px(X + 1, Y + 1, P['cap'])
    else:
        c.rect(X, g0 + 1, 8, 2, P['shade'])
        c.baseball(X, Y, 3, C['poleL']); c.px(X + 2, Y + 2, C['greyL']); c.px(X + 1, Y + 3, C['greyL'])
    # in front of the ball: everything past the wall, lit from the left
    wall_x, wall_top = fr.x(WALL), fr.y(WALL_H)
    c.rect(wall_x, wall_top, W - wall_x, g0 - wall_top, P['wall'])
    c.rect(wall_x, wall_top + 1, W - wall_x, 1, C['wallL'])
    bayer_gradient(c, wall_x, wall_top + 2, W - wall_x, max(1, g0 - wall_top - 2), P['wall'], C['wallD'])
    f = WALL + 20
    while fr.x(f) < W:
        c.rect(fr.x(f), wall_top + 1, 1, g0 - wall_top - 1, C['wallD']); f += 20
    c.rect(wall_x, wall_top, W - wall_x, 1, P['score'])
    c.rect(wall_x, wall_top - 1, 2, g0 - wall_top + 1, C['poleL'])
    tiers(c, fr, C['greyDD'], C['s6'], under=C['greyD'], edge=C['s6'])
    crowd_rows(c, fr, 12, [C['skin'], C['rim'], C['skinD']],
               [C['red'], C['redL'], C['greyL'], CX['crowdA'], CX['crowdB'], C['greyD'], C['s2']], aisle=C['greyD'])
    # the upper deck's roof throws its shadow down the top rows
    top_y = fr.y(TOP)
    for yy in range(int(top_y) + 2, int(top_y) + (12 if cam == 'close' else 7)):
        for x in range(int(fr.x(WALL + 40)), W):
            t = 1 - (yy - top_y) / (12 if cam == 'close' else 7)
            if yy > fr.y(stands_h((x - fr.ox) / fr.scale)) + 1 and c.get(x, yy) != C['s6'] and t * 0.8 > (BAYER[yy % 4][x % 4] + .5) / 16:
                c.set(x, yy, C['greyDD'])
    foul_pole(c, fr, C['poleL'], C['poleD'], C['poleD'])
    board(c, fr, C['greyDD'], C['greyD'], INK, [C['greyL'], C['s6']], C['sun'], lip=C['s6'], glow=C['s6'])
    flags(c, fr, C['greyL'], C['red'], C['redDD'])
    wall_h = WALL_H * fr.scale
    ly = g0 - wall_h + 3 if wall_h >= 11 else g0 - wall_h - 8
    c.rect(wall_x + 5, ly - 1, 13, 7, INK); c.t3(wall_x + 6, ly, '395', P['score'])
    hud(c, fr, i, shadow=INK)
    return c


SIDES = {'now': now_side, 'a': a_side, 'b': b_side, 'c': c_side}

if __name__ == '__main__':
    print('flight: %.0f ft, apex %.0f ft' % (DIST, APEX))
    os.makedirs(OUT, exist_ok=True)
    for tag in (sys.argv[1:] or list(SIDES)):
        used = {}
        for cam in ('wide', 'close'):
            cv = SIDES[tag](cam)
            cv.png(os.path.join(OUT, f'{tag}-{cam}.png'), 4)
            used.update(cv.used())
        print(tag, len(used), 'colours in the side view')
        json.dump([hexof(k) for k in used], open(os.path.join(OUT, f'{tag}-side-colours.json'), 'w'))
