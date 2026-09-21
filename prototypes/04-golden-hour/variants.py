"""The three polish variants, plus the build entry point: python3 variants.py [now a b c]"""
import os, sys, json
from engine import *
import now

W, H = 320, 224
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'targets')


# ======================================================================================
# Shared rig: a batter built from capsules, shaded by one light (or left flat)
# ======================================================================================

def bat_part(s, x0, y0, x1, y1, M, r0=1.0, r1=2.5):
    s.part(m_capsule(x0, y0, r0, x1, y1, r1), M['bat'], M.get('line_bat'))
    dx, dy = x1 - x0, y1 - y0
    n = math.hypot(dx, dy)
    # the knob: a touch wider than the handle, just behind the hands
    s.part(m_capsule(x0 - dx / n * 2.5, y0 - dy / n * 2.5, r0 + .8, x0 - dx / n * 1.5, y0 - dy / n * 1.5, r0 + .8),
           M['bat'], M.get('line_bat'))


REAL_POSES = {
    0: dict(kl=(-7, -17), al=(-7, -4), kr=(8, -18), ar=(8, -4), sh=(5, -51), el=(12, -45), hd=(13.5, -54),
            tip=(22, -87), far=(-3, -50)),
    1: dict(kl=(-5, -16), al=(-8, -4), kr=(10, -17), ar=(11, -4), sh=(6, -50), el=(14, -46), hd=(21, -43),
            tip=(63, -58), far=(-2, -49)),
    2: dict(kl=(-6, -17), al=(-8, -4), kr=(9, -17), ar=(10, -4), sh=(-3, -50), el=(-10, -44), hd=(-16, -40),
            tip=(-41, -57), far=(4, -49)),
}


def real_batter(frame, M, light=(-0.6, -0.8), cuts=(0.35, -0.3), inner=False, number=None, face=None):
    s = Sprite(128, 100, 50, 97, light, cuts, inner)
    p = REAL_POSES[frame]
    hl, hr = (-4, -31), (4, -31)
    # shoes first, toes toward the plate
    for ax, ay in (p['al'], p['ar']):
        s.part(m_ellipse(ax + 1.5, ay + 2, 5.5, 2.4), M['shoe'], M.get('line_shoe'))
    for hip, knee, ank in ((hl, p['kl'], p['al']), (hr, p['kr'], p['ar'])):
        s.part(m_capsule(knee[0], knee[1], 3.6, ank[0], ank[1], 2.6), M['sock'], M.get('line_sock'))
        mid = ((knee[0] + ank[0]) / 2, (knee[1] + ank[1]) / 2 - 1)
        s.part(m_capsule(knee[0], knee[1], 3.9, mid[0], mid[1], 3.3), M['pants'], M.get('line_pants'))
        s.part(m_capsule(hip[0], hip[1], 5.2, knee[0], knee[1], 4.0), M['pants'], M.get('line_pants'))
    s.part(m_poly([(-8, -54), (-2, -57), (7, -55), (9, -44), (7, -30), (-7, -30), (-9, -42)]),
           M['jersey'], M.get('line_jersey'))
    s.part(m_ellipse(-0.5, -53, 8.6, 3.6), M['jersey'], None)
    s.part(m_poly([(-7.5, -33), (7.5, -33), (7.5, -30), (-7.5, -30)]), M['belt'], None)
    if number:
        s.lstamp(number[0], number[1], -5, -48)
    # neck, head, helmet
    s.part(m_poly([(0, -58), (5, -58), (5, -54), (0, -54)]), M['skin'], None)
    s.part(m_ellipse(3, -61.5, 5.2, 5.6), M['skin'], M.get('line_skin'))
    helmet = [q for q in m_ellipse(2, -63, 7, 6) if q[1] < -61]
    s.part(helmet, M['helmet'], M.get('line_helmet'))
    s.part(m_poly([(-4, -62), (1, -62), (1, -56), (-3, -56), (-4, -58)]), M['helmet'], M.get('line_helmet'))
    s.part(m_poly([(7, -63), (12, -62), (12, -61), (7, -61)]), M['brim'], None)
    if face:
        s.lstamp(face[0], face[1], 5, -61)
    # arms and the bat
    s.part(m_capsule(p['far'][0], p['far'][1], 3.0, p['hd'][0], p['hd'][1] + 3, 2.2),
           M.get('farsleeve', M['sleeve']), M.get('line_farsleeve', M.get('line_sleeve')))
    bat_part(s, p['hd'][0], p['hd'][1] + 2, p['tip'][0], p['tip'][1], M)
    s.part(m_capsule(p['sh'][0], p['sh'][1], 3.4, p['el'][0], p['el'][1], 2.8), M['sleeve'], M.get('line_sleeve'))
    s.part(m_capsule(p['el'][0], p['el'][1], 2.8, p['hd'][0], p['hd'][1] + 1, 2.3), M['arm'], M.get('line_arm'))
    s.part(m_ellipse(p['hd'][0], p['hd'][1], 2.7, 3.2), M['hand'], M.get('line_hand'))
    return s


# ======================================================================================
# A — SAME SIXTEEN. docs/palette.md and not one hex more; the fidelity is all drawing.
# ======================================================================================

A_PITCHER = {
    0: ["...RRR...",
        "..RRRRR..",
        "..RRRRRR.",
        "...SSS...",
        "...SSS...",
        "..KKKKK..",
        ".KKKKKKK.",
        ".KKGGKKK.",
        ".KKGGKKK.",
        ".KKKKKKK.",
        "..KKKKK..",
        "..KKKKK..",
        "..KK.KK..",
        "..KK.KK..",
        "..KK.KK..",
        "..RR.RR..",
        "..RR.RR..",
        "..KK.KKK."],
    1: ["...RRR....S.",
        "..RRRRR...K.",
        "..RRRRRR.KK.",
        "...SSS...K..",
        "...SSS..KK..",
        "..KKKKKKK...",
        ".KKKKKKK....",
        "GGKKKKKK....",
        "GGKKKKK.....",
        "..KKKKK.....",
        "..KKKKKKKK..",
        "..KKK..KKK..",
        "..KK....RR..",
        "..KK....RR..",
        "..KK....KKK.",
        "..RR........",
        "..RR........",
        "..KKK......."],
    2: ["....RRR.....",
        "...RRRRR....",
        "...RRRRRR...",
        "....SSS.....",
        "....SSS.....",
        "..KKKKKKK...",
        ".KKKKKKKKK..",
        "GGKKKKKK.KK.",
        "GG.KKKKK..KK",
        "...KKKKK...S",
        "...KKKKK....",
        "..KKK.KKK...",
        ".KKK...KKK..",
        ".KK.....KK..",
        ".RR.....RR..",
        ".RR.....RR..",
        "KKK.....KKK."],
}


def a_mat():
    k = P['ink']
    return dict(shoe=k, sock=P['cap'], pants=k, jersey=k, belt=k, skin=P['skin'], helmet=P['cap'],
                brim=P['cap'], sleeve=P['cap'], farsleeve=k, arm=k, hand=P['skin'], bat=P['bat'])


def a_batter(frame):
    return real_batter(frame, a_mat())


def a_pitcher(frame):
    rows = A_PITCHER[frame]
    s = Sprite(40, 40, 16, 36)
    leg = {'R': P['cap'], 'S': P['skin'], 'K': P['ink'], 'G': P['bat']}
    s.lstamp(rows, leg, -4, -len(rows))
    return s


def round_cloud(c, x, base, bumps, body, under):
    pts = set()
    for dx, r in bumps:
        for px_, py_, _, _ in m_ellipse(x + dx, base - r * 0.55, r, r):
            if py_ < base:
                pts.add((px_, py_))
    for px_, py_ in pts:
        low = py_ >= base - 1 or ((px_, py_ + 1) not in pts)
        c.set(px_, py_, under if low else body)


A_CLOUDS = [(38, 40, [(3, 4), (9, 7), (17, 5), (23, 3)]),
            (196, 58, [(2, 3), (8, 6), (15, 4)]),
            (262, 33, [(3, 4), (10, 8), (19, 9), (27, 5), (32, 3)])]


def perspective_bands(c, y0, a, b, heights=(3, 3, 4, 4, 5, 6, 7, 8, 10, 12, 14, 17, 20, 24)):
    y = y0
    for i, h in enumerate(heights):
        c.rect(0, y, W, h, b if i % 2 == 0 else a)
        y += h
        if y >= H:
            break


def round_treeline(c, body, seed, baseline=96, rise=10, x0=0, x1=W, gap=(5, 9), under=None):
    g = random.Random(seed)
    x = x0 - 6
    while x < x1:
        w = g.randint(*gap)
        tall = g.randint(0, 4) == 0
        h = max(4, round(rise * (g.uniform(1.05, 1.35) if tall else g.uniform(0.45, 0.85))))
        r = w / 2 + 0.5
        c.rect(x, baseline - h + r, w, h - r + 1, body)
        c.ellipse(x + w / 2, baseline - h + r, r, r, body)
        if under is not None:
            c.rect(x + 1, baseline - 2, w - 1, 2, under)
        x += w - 1


def a_scene():
    c = Canvas(W, H)
    c.rect(0, 0, W, H, P['sky1'])
    c.rect(0, 44, W, 26, P['sky2'])
    c.rect(0, 70, W, 26, P['sky3'])
    c.dither(0, 42, W, 4, P['sky1'], P['sky2'])
    c.dither(0, 68, W, 4, P['sky2'], P['sky3'])
    for x, base, bumps in A_CLOUDS:
        round_cloud(c, x, base, bumps, P['chalk'], P['sky3'])
    round_treeline(c, P['sky2'], 12)
    # the near landmark: a water tower with a roof, a shaded belly and braced legs
    tx, tb = 248, 96
    c.rect(tx - 6, tb - 18, 13, 8, P['wall'])
    c.rect(tx - 5, tb - 19, 11, 1, P['wall'])
    c.rect(tx - 3, tb - 20, 7, 1, P['shade'])
    c.rect(tx - 1, tb - 21, 3, 1, P['shade'])
    c.rect(tx - 6, tb - 13, 13, 3, P['shade'])
    c.rect(tx - 5, tb - 10, 11, 1, P['shade'])
    for lx in (-5, 5):
        c.rect(tx + lx, tb - 9, 1, 9, P['wall'])
    c.line(tx - 5, tb - 9, tx + 5, tb - 1, P['wall'])
    c.line(tx + 5, tb - 9, tx - 5, tb - 1, P['wall'])
    c.rect(tx, tb - 9, 1, 9, P['shade'])
    # foul poles with a cap
    for x in (40, 280):
        c.rect(x, 96 - 28, 2, 28, P['score'])
        c.rect(x - 1, 96 - 29, 4, 1, P['score'])
    # the wall: panel seams, a shadowed foot, the same chalk cap
    c.rect(0, 96, W, 8, P['wall'])
    for x in range(8, W, 16):
        c.rect(x, 98, 1, 6, P['shade'])
    c.rect(0, 103, W, 1, P['shade'])
    c.rect(0, 96, W, 1, P['chalk'])
    # warning track, then grass mown in perspective
    c.rect(0, 104, W, 4, P['dirt'])
    c.rect(0, 104, W, 1, P['dirtD'])
    c.rect(0, 108, W, H - 108, P['grassA'])
    perspective_bands(c, 108, P['grassA'], P['grassB'])
    # the scoreboard: a dark face inside the green frame
    c.rect(127, 79, 66, 17, P['wall'])
    c.rect(127, 79, 66, 1, P['chalk'])
    c.rect(130, 82, 60, 14, P['ink'])
    c.t3(134, 84, now.FEET, P['score'])
    c.t3(134, 91, now.PARK, P['chalk'])
    for i in range(3):
        c.rect(168 + i * 5, 84, 3, 3, P['score'] if i < 1 else P['wall'])
    now.flags(c)
    # foul lines: a pixel wide out by the wall, two by the plate
    for ex in (40, 280):
        c.line(160, 196, ex, 104, P['chalk'])
        mx = (160 + ex) / 2
        c.line(160 + (1 if ex > 160 else -1), 196, mx, 150, P['chalk'])
    # the mound and the dirt around the plate, round, with a shaded lip
    c.ellipse(160, 120, 15, 4.5, P['dirtD'])
    c.ellipse(160, 119, 14, 3.6, P['dirt'])
    c.rect(157, 117, 6, 1, P['chalk'])
    c.ellipse(160, 205, 93, 25, P['dirtD'])
    c.ellipse(160, 205.5, 91, 23.5, P['dirt'])
    for sgn in (-1, 1):   # batter's boxes
        pts = [(160 + sgn * 22, 189), (160 + sgn * 68, 189), (160 + sgn * 82, 221), (160 + sgn * 26, 221)]
        for i in range(4):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % 4]
            c.line(x0, y0, x1, y1, P['chalk'])
    for j, (x0, x1) in enumerate([(152, 168), (152, 168), (153, 167), (155, 165), (157, 163), (159, 161)]):
        c.rect(x0, 190 + j, x1 - x0, 1, P['chalk'])
    # people
    ps = a_pitcher(2)
    c.blit(ps, 160 - ps.ox, 117 - ps.oy)
    now.zone(c, P['chalk'])
    bs = a_batter(0)
    c.blit(bs, 104 - bs.ox, 222 - bs.oy)
    bx, by, r = now.BALL
    c.baseball(bx, by, r, P['sky3'])
    c.px(bx + r, by, P['ink'])
    c.t3(8, H - 12, '87 MPH', P['chalk'])
    c.t3(8, 8, now.HUD, P['chalk'])
    return c


# ======================================================================================
# B — TWO LINES. A second 16-colour line for people and props: three-step ramps, a dark
# contour, big heads. The platformer school.
# ======================================================================================

B = {k: col(v) for k, v in dict(
    redD='#880022', red='#CC2222', redL='#EE6666',
    skinD='#CC8866', skin='#EEAA88', skinL='#EECCAA', blush='#EE6666',
    whiteD='#AAAACC', white='#EEEEEE', lineW='#666688',
    shoeL='#666688', shoe='#444466',
    woodD='#884422', wood='#CC8844', woodL='#EECC88',
    dirtL='#EEAA66', grassL='#66CC44', wallL='#44AA66', wallD='#004422',
    haze='#88AACC', hill='#66AA88', sky4='#CCEEEE', cloudD='#88AACC',
    poleL='#EEEE88', poleD='#AA6622', glove='#AA6622', gloveD='#884422',
).items()}
INK = P['ink']

CHIBI_POSES = {
    0: dict(al=(-8, -5), ar=(9, -5), sh=(7, -34), el=(15, -29), hd=(20, -37), tip=(29, -85)),
    1: dict(al=(-9, -5), ar=(11, -5), sh=(8, -34), el=(15, -31), hd=(23, -33), tip=(64, -50)),
    2: dict(al=(-8, -5), ar=(10, -5), sh=(-6, -34), el=(-13, -30), hd=(-20, -30), tip=(-45, -50)),
}


def b_batter(frame):
    s = Sprite(132, 104, 52, 100, light=(-0.6, -0.8), cuts=(0.4, -0.25), inner=True)
    p = CHIBI_POSES[frame]
    red = [B['redD'], B['red'], B['redL']]
    white = [B['whiteD'], B['white'], B['white']]
    skin = [B['skinD'], B['skin'], B['skinL']]
    wood = [B['woodD'], B['wood'], B['woodL']]
    shoe = [INK, B['shoe'], B['shoeL']]
    for ax, ay in (p['al'], p['ar']):
        s.part(m_ellipse(ax + 2, ay + 2, 7, 3.6), shoe, INK)
    for hip, ank in (((-5, -20), p['al']), ((5, -20), p['ar'])):
        s.part(m_capsule(hip[0], hip[1], 5.4, ank[0], ank[1], 4.4), white, B['lineW'])
        mx, my = (hip[0] + ank[0] * 3) / 4, (hip[1] + ank[1] * 3) / 4
        s.part(m_capsule(mx, my, 4.5, ank[0], ank[1], 4.4), red, B['redD'])
    torso = m_ellipse(0, -30, 10.5, 11.5)
    s.part(torso, white, B['lineW'])
    s.part([q for q in torso if -22 <= q[1] <= -20], INK, None)
    s.lset(4, -21, P['score']); s.lset(5, -21, P['score'])
    # far arm, then the bat, then the head over both
    s.part(m_capsule(-2, -35, 3.6, p['hd'][0], p['hd'][1] + 4, 3.2), red, B['redD'])
    bat_part(s, p['hd'][0], p['hd'][1] + 3, p['tip'][0], p['tip'][1], dict(bat=wood, line_bat=B['woodD']), 1.7, 3.7)
    s.part(m_ellipse(2, -51, 12, 11.5), skin, B['skinD'])
    s.part([q for q in m_ellipse(1, -55, 13.5, 12) if q[1] < -52], red, B['redD'])
    s.part(m_poly([(-12, -53), (-2, -53), (-2, -44), (-8, -43), (-12, -47)]), red, B['redD'])
    s.part(m_poly([(8, -55), (21, -53), (22, -51), (8, -51)]), [B['redD'], B['redD'], B['red']], B['redD'])
    s.lstamp(["WW", "W."], {'W': P['chalk']}, -5, -63)          # the helmet's glint
    s.lset(-7, -48, B['redD']); s.lset(-6, -48, B['redD'])        # ear hole
    s.lstamp(["KK", "KK", "KK", "KK"], {'K': INK}, 9, -49)       # the eye, on the ball
    s.lset(9, -49, P['chalk'])
    s.lstamp(["SS", "SS"], {'S': B['skinL']}, 14, -46)           # nose
    s.lset(11, -43, B['blush']); s.lset(12, -43, B['blush']); s.lset(11, -42, B['blush'])
    s.lset(9, -41, B['skinD']); s.lset(10, -41, B['skinD'])
    # the near arm and the hands
    s.part(m_capsule(p['sh'][0], p['sh'][1], 4.0, p['el'][0], p['el'][1], 3.6), red, B['redD'])
    s.part(m_capsule(p['el'][0], p['el'][1], 3.5, p['hd'][0], p['hd'][1] + 1, 3.2), skin, B['skinD'])
    s.part(m_ellipse(p['hd'][0], p['hd'][1], 3.9, 4.2), skin, B['skinD'])
    s.outline(INK)
    return s


B_PITCHER = {
    0: ["....RRRRR....",
        "...RHHRRRR...",
        "..RRHRRRRRr..",
        "..RRRRRRRRr..",
        ".rrrrrrrrrrr.",
        "..SSSSSSSSs..",
        "..SKSSSSKSs..",
        "..SSSSSSSSs..",
        "...SSSSSSs...",
        "..WWWWWWWWw..",
        ".WWWGGGGWWWw.",
        ".WWGGGGGgWWw.",
        ".SSGGGGggSSs.",
        "..WWGGggWWw..",
        "..KKKKKKKKK..",
        "..WWWWwWWWw..",
        "..WWWW.WWWw..",
        "..RRRR.RRRr..",
        "..RRRR.RRRr..",
        ".KKKKK.KKKKK."],
    1: ["....RRRRR.....BB",
        "...RHHRRRR....SS",
        "..RRHRRRRRr..RR.",
        "..RRRRRRRRr.RR..",
        ".rrrrrrrrrrrRR..",
        "..SSSSSSSSsRR...",
        "..SKSSSSKSsR....",
        "..SSSSSSSSs.....",
        "...SSSSSSs......",
        "GGWWWWWWWWw.....",
        "GGGWWWWWWWw.....",
        "GGgWWWWWWWWWw...",
        ".g.WWWWWWWWWWw..",
        "...KKKKKKWWWWw..",
        "...WWWWw..RRRr..",
        "...WWWWw..RRRr..",
        "...WWWWw..KKKK..",
        "...RRRRr........",
        "...RRRRr........",
        "..KKKKKK........"],
    2: [".....RRRRR......",
        "....RHHRRRR.....",
        "...RRHRRRRRr....",
        "...RRRRRRRRr....",
        "..rrrrrrrrrrr...",
        "...SSSSSSSSs....",
        "...SKSSSSKSs....",
        "...SSSSSSSSs....",
        "....SSSSSSs.....",
        "GG.WWWWWWWWRr...",
        "GGGWWWWWWWWRRRr.",
        "GGgWWWWWWWw.RRSS",
        ".g.WWWWWWWw..SSS",
        "...KKKKKKKK.....",
        "..WWWWw.WWWWw...",
        ".WWWWw...WWWWw..",
        ".RRRr.....RRRr..",
        ".RRRr.....RRRr..",
        "KKKKK.....KKKKK."],
}


def b_pitcher(frame):
    rows = B_PITCHER[frame]
    s = Sprite(48, 44, 18, 40)
    leg = {'R': B['red'], 'r': B['redD'], 'H': B['redL'], 'S': B['skin'], 's': B['skinD'], 'K': INK,
           'W': B['white'], 'w': B['whiteD'], 'G': B['glove'], 'g': B['gloveD'], 'B': P['chalk']}
    s.lstamp(rows, leg, -6, -len(rows))
    s.outline(INK)
    return s


def puffy_cloud(c, x, base, bumps):
    own = {}
    for dx, r in bumps:
        for px_, py_, nx, ny in m_ellipse(x + dx, base - r * 0.6, r, r):
            if py_ < base:
                own[(px_, py_)] = (nx, ny)
    for (px_, py_), (nx, ny) in own.items():
        l = nx * -0.6 + ny * -0.8
        tone = P['chalk'] if l > -0.35 else P['sky3']
        if py_ >= base - 1:
            tone = B['cloudD']
        elif py_ >= base - 3 and tone == P['chalk']:
            tone = P['sky3']
        c.set(px_, py_, tone)


B_CLOUDS = [(30, 42, [(4, 5), (12, 9), (22, 7), (30, 4)]),
            (190, 60, [(3, 4), (10, 7), (18, 5), (24, 3)]),
            (250, 36, [(4, 5), (13, 10), (25, 12), (37, 8), (45, 4)])]


def hills(c, colour, top, seed, baseline=96, r=(22, 40), crest=None):
    g = random.Random(seed)
    x = -20
    while x < W + 20:
        rad = g.randint(*r)
        cy = baseline + rad - g.randint(int(top * 0.55), top)
        for px_, py_, nx, ny in m_ellipse(x, cy, rad, rad):
            if py_ < baseline:
                c.set(px_, py_, crest if (crest and ny < -0.93) else colour)
        x += int(rad * g.uniform(0.9, 1.5))


def canopies(c, seed, baseline=96, skip=()):
    g = random.Random(seed)
    items = []
    x = -4
    while x < W + 4:
        rad = g.choice((4, 5, 5, 6, 7))
        items.append((x, baseline - g.randint(2, 7), rad))
        x += g.randint(5, 9)
    g.shuffle(items)
    for x, cy, rad in items:
        if any(a <= x <= b for a, b in skip):
            continue
        for px_, py_, nx, ny in m_ellipse(x, cy, rad, rad):
            if py_ >= baseline:
                continue
            l = nx * -0.6 + ny * -0.8
            c.set(px_, py_, B['grassL'] if l > 0.45 else (P['shade'] if l < -0.2 else P['grassB']))


def tufts(c, seed, light, dark, y0=112, keepout=(142, 128, 198, 190)):
    g = random.Random(seed)
    for _ in range(230):
        y = int(y0 + (H - y0) * g.random() ** 0.8)
        x = g.randint(0, W - 4)
        if keepout[0] <= x <= keepout[2] and keepout[1] <= y <= keepout[3]:
            continue
        here = c.get(x, y)
        if here not in (P['grassA'], P['grassB']):
            continue
        tone = light if g.random() < 0.6 else dark
        depth = (y - y0) / (H - y0)
        c.set(x, y, tone)
        if depth > 0.25 and c.get(x + 2, y) == here:
            c.set(x + 1, y - 1, tone); c.set(x + 2, y, tone)
        if depth > 0.6 and c.get(x + 4, y) == here:
            c.set(x + 3, y - 1, tone); c.set(x + 4, y, tone)


def speckle(c, seed, region, n, tones, on):
    g = random.Random(seed)
    x0, y0, x1, y1 = region
    for _ in range(n):
        x, y = g.randint(x0, x1), g.randint(y0, y1)
        if c.get(x, y) == on and c.get(x + 1, y) == on:
            t = g.choice(tones)
            c.set(x, y, t)
            if g.random() < 0.4:
                c.set(x + 1, y, t)


def b_scene():
    c = Canvas(W, H)
    c.rect(0, 0, W, H, P['sky1'])
    c.rect(0, 44, W, 26, P['sky2'])
    c.rect(0, 70, W, 16, P['sky3'])
    c.rect(0, 86, W, 10, B['sky4'])
    c.dither(0, 42, W, 4, P['sky1'], P['sky2'])
    c.dither(0, 68, W, 4, P['sky2'], P['sky3'])
    c.dither(0, 84, W, 4, P['sky3'], B['sky4'])
    for x, base, bumps in B_CLOUDS:
        puffy_cloud(c, x, base, bumps)
    hills(c, B['haze'], 22, 5, r=(30, 52))
    hills(c, B['hill'], 13, 9, r=(18, 30), crest=B['wallL'])
    canopies(c, 21, skip=((120, 200), (238, 258)))
    # the water tower, red band and all, contoured in ink
    tx, tb = 248, 96
    t = Sprite(24, 30, 12, 29)
    t.part(m_ellipse(0, -18, 8.5, 6.5), [B['whiteD'], B['white'], B['white']])
    t.part([q for q in m_ellipse(0, -18, 8.5, 6.5) if -19 <= q[1] <= -17], [B['redD'], B['red'], B['redL']])
    t.part(m_poly([(-6, -24), (0, -28), (6, -24)]), [B['redD'], B['red'], B['redL']])
    for lx in (-6, 5):
        t.part(m_poly([(lx, -12), (lx + 2, -12), (lx + 2, 0), (lx, 0)]), B['shoeL'])
    t.lstamp(["K.........K", ".KK.....KK.", "...KK.KK...", ".....K.....", "...KK.KK...", ".KK.....KK."],
             {'K': B['shoe']}, -5, -9)
    t.outline(INK)
    c.blit(t, tx - t.ox, tb - t.oy)
    # foul poles: a lit side and a shaded side
    for x in (40, 280):
        c.rect(x, 96 - 28, 1, 28, B['poleL']); c.rect(x + 1, 96 - 28, 1, 28, B['poleD'])
        c.rect(x - 1, 96 - 30, 4, 2, P['score'])
    # the wall: planks, a lit top edge, a yellow rail
    c.rect(0, 96, W, 8, P['wall'])
    c.rect(0, 97, W, 1, B['wallL'])
    for x in range(4, W, 8):
        c.rect(x, 98, 1, 6, P['shade'])
    c.rect(0, 103, W, 1, B['wallD'])
    c.rect(0, 96, W, 1, P['score'])
    # warning track and grass
    c.rect(0, 104, W, 4, P['dirt'])
    c.rect(0, 104, W, 1, B['woodD'])
    speckle(c, 3, (0, 105, W - 2, 107), 60, [B['dirtL'], P['dirtD']], P['dirt'])
    c.rect(0, 108, W, H - 108, P['grassA'])
    perspective_bands(c, 108, P['grassA'], P['grassB'])
    tufts(c, 7, B['grassL'], P['shade'])
    # the scoreboard: ink contour, bevelled frame, dark face, bulbs
    c.rect(125, 77, 70, 19, INK)
    c.rect(126, 78, 68, 18, P['wall'])
    c.rect(126, 78, 68, 1, B['wallL']); c.rect(126, 78, 1, 18, B['wallL'])
    c.rect(129, 81, 62, 15, INK)
    c.rect(130, 82, 60, 14, B['wallD'])
    c.t3(134, 84, now.FEET, P['score'])
    c.t3(134, 91, now.PARK, P['chalk'])
    for i in range(3):
        c.rect(168 + i * 5, 84, 3, 3, P['score'] if i < 1 else P['wall'])
        if i < 1:
            c.px(168 + i * 5, 84, B['poleL'])
    for dx in (6, 55):
        x = 128 + dx
        c.rect(x, 69, 1, 8, P['chalk'])
        for j in range(3):
            c.rect(x + 1, 69 + j, 5 - j, 1, P['cap'] if j < 2 else B['redD'])
    # foul lines
    for ex in (40, 280):
        c.line(160, 196, ex, 104, P['chalk'])
        c.line(160 + (1 if ex > 160 else -1), 196, (160 + ex) / 2, 150, P['chalk'])
    # the mound: lit on top, shaded under
    c.ellipse(160, 120.5, 16, 5, P['dirtD'])
    c.ellipse(160, 119, 15, 4, P['dirt'])
    c.ellipse(157, 118, 9, 1.6, B['dirtL'])
    c.rect(157, 117, 6, 1, P['chalk'])
    # the plate circle
    c.ellipse(160, 205, 94, 25.5, B['woodD'])
    c.ellipse(160, 205.2, 93, 24.6, P['dirtD'])
    c.ellipse(160, 206, 91, 23.5, P['dirt'])
    speckle(c, 11, (70, 184, 250, 223), 120, [B['dirtL'], B['dirtL'], P['dirtD']], P['dirt'])
    for sgn in (-1, 1):
        pts = [(160 + sgn * 22, 189), (160 + sgn * 68, 189), (160 + sgn * 82, 221), (160 + sgn * 26, 221)]
        for i in range(4):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % 4]
            c.line(x0, y0, x1, y1, P['chalk'])
    for j, (x0, x1) in enumerate([(152, 168), (152, 168), (153, 167), (155, 165), (157, 163), (159, 161)]):
        c.rect(x0, 190 + j, x1 - x0, 1, P['chalk'])
        c.px(x1 - 1, 190 + j, B['whiteD']); c.px(x0, 190 + j + 1, P['dirtD']) if j > 1 else None
    # people, each standing on a small shadow
    c.ellipse(160, 117.5, 8, 1.6, P['dirtD'])
    ps = b_pitcher(2)
    c.blit(ps, 160 - ps.ox, 118 - ps.oy)
    now.zone(c, P['chalk'])
    c.ellipse(105, 221, 20, 3, P['dirtD'])
    bs = b_batter(0)
    c.blit(bs, 104 - bs.ox, 223 - bs.oy)
    bx, by, r = now.BALL
    c.baseball(bx, by, r, P['sky3'], outline=INK)
    c.t3(8, H - 12, '87 MPH', P['chalk'], shadow=INK)
    c.t3(8, 8, now.HUD, P['chalk'], shadow=INK)
    return c


# ======================================================================================
# C — GOLDEN HOUR. Three lines, no contour at all: form comes from one low sun, rim light,
# cast shadows and ordered dither. The Genesis sports-cart school.
# ======================================================================================

C = {k: col(v) for k, v in dict(
    s0='#222266', s1='#444488', s2='#6666AA', s3='#AA88AA', s4='#CC8888', s5='#EEAA88', s6='#EECC88',
    sun='#EEEEAA', far='#886688', mid='#664466', treeD='#224444', treeRim='#CCAA66',
    redDD='#660022', redD='#AA2222', red='#CC2222', redL='#EE8866',
    skinDD='#884444', skinD='#CC8866', skin='#EEAA88', rim='#EECCAA',
    greyDD='#444466', greyD='#666688', grey='#8888AA', greyL='#AAAACC', greyRim='#CCAAAA',
    woodDD='#442222', woodD='#884422', wood='#AA8844', woodL='#EECC88',
    wallD='#004422', wallL='#44AA66', dirtL='#EEAA66', dirtDD='#884422', poleD='#CCAA22', poleL='#EEEE88',
).items()}
C_LIGHT = (0.85, -0.5)


def c_mat():
    red = [C['redDD'], C['redD'], C['red'], C['redL']]
    grey = [C['greyDD'], C['greyD'], C['grey'], C['greyRim']]
    skin = [C['skinDD'], C['skinD'], C['skin'], C['rim']]
    wood = [C['woodDD'], C['woodD'], C['wood'], C['woodL']]
    return dict(shoe=[INK, INK, C['greyDD'], C['grey']], sock=red, pants=grey, jersey=grey, belt=INK,
                skin=skin, helmet=red, brim=C['redD'], sleeve=red, farsleeve=[C['greyDD'], C['greyDD'], C['greyD']],
                arm=skin, hand=skin, bat=wood,
                line_pants=C['greyDD'], line_farsleeve=C['greyDD'], line_sleeve=C['redDD'], line_arm=C['skinDD'], line_hand=C['skinDD'],
                line_bat=C['woodDD'], line_helmet=C['redDD'], line_sock=C['redDD'])


def c_batter(frame):
    num = (["RRR", "..R", ".R.", ".R.", ".R."], {'R': C['redD']})
    face = (["DDD", ".K.", "...", "..D"], {'D': C['skinDD'], 'K': INK})
    return real_batter(frame, c_mat(), light=C_LIGHT, cuts=(0.3, -0.35), inner=True, number=num, face=face)


C_PITCHER = {
    0: ["...rRR...",
        "..rRRRW..",
        "..rRRRRR.",
        "...sSS...",
        "...sSS...",
        "..uUULL..",
        ".uUUUULW.",
        ".uUGGULW.",
        ".uUGgULW.",
        ".uUUUULW.",
        "..uUULL..",
        "..uUULL..",
        "..uU.UL..",
        "..uU.UL..",
        "..uU.UL..",
        "..rR.RR..",
        "..rR.RR..",
        "..KK.KKK."],
    1: ["...rRR....S.",
        "..rRRRW...L.",
        "..rRRRRR.UL.",
        "...sSS...U..",
        "...sSS..UL..",
        "..uUUULLL...",
        ".uUUUULW....",
        "GGUUUULW....",
        "GgUUUUL.....",
        "..uUUUL.....",
        "..uUUULLLW..",
        "..uUU..ULW..",
        "..uU....RR..",
        "..uU....RR..",
        "..uU....KKK.",
        "..rR........",
        "..rR........",
        "..KKK......."],
    2: ["....rRR.....",
        "...rRRRW....",
        "...rRRRRR...",
        "....sSS.....",
        "....sSS.....",
        "..uUUULLL...",
        ".uUUUUULLW..",
        "GGUUUUUL.LW.",
        "Gg.uUUUL..LW",
        "...uUUUL...S",
        "...uUUUL....",
        "..uUU.ULW...",
        ".uUU...ULW..",
        ".uU.....UL..",
        ".rR.....RR..",
        ".rR.....RR..",
        "KKK.....KKK."],
}


def c_pitcher(frame):
    rows = C_PITCHER[frame]
    s = Sprite(40, 40, 16, 36)
    leg = {'R': C['red'], 'r': C['redD'], 'S': C['skin'], 's': C['skinD'], 'U': C['grey'], 'u': C['greyDD'],
           'L': C['greyL'], 'W': C['rim'], 'K': INK, 'G': C['woodD'], 'g': C['woodDD']}
    s.lstamp(rows, leg, -4, -len(rows))
    return s


SHADOW = {P['grassA']: P['shade'], P['grassB']: P['shade'], P['dirt']: P['dirtD'], P['dirtD']: C['dirtDD'],
          C['dirtL']: P['dirtD']}


def cast_shadow(c, sp, fx, fy, k=0.95, rise=0.12, soft_from=58):
    for y in range(sp.h):
        for x in range(sp.w):
            if sp.p[y][x] is None:
                continue
            lx, hgt = x - sp.ox, sp.oy - y
            sx, sy = int(fx + lx - hgt * k), int(fy - hgt * rise)
            if hgt > soft_from and ((sx + sy) & 1):
                continue
            base = c.get(sx, sy)
            if base in SHADOW:
                c.set(sx, sy, SHADOW[base])


def c_sky(c):
    stops = [(0, 's0'), (8, 's0'), (22, 's1'), (28, 's1'), (42, 's2'), (46, 's2'), (58, 's3'), (61, 's3'),
             (70, 's4'), (73, 's4'), (81, 's5'), (84, 's5'), (92, 's6'), (96, 's6')]
    for (y0, a), (y1, b) in zip(stops, stops[1:]):
        if a == b:
            c.rect(0, y0, W, y1 - y0, C[a])
        else:
            bayer_gradient(c, 0, y0, W, y1 - y0, C[a], C[b])


def streak(c, x, y, rx, ry):
    for px_, py_, nx, ny in m_ellipse(x, y, rx, ry):
        tone = C['s3'] if ny < -0.35 else (C['s6'] if (ny > 0.45 and nx > -0.5) else (C['s5'] if ny > 0.05 else C['s4']))
        if abs(nx) > 0.78 and ((px_ + py_) & 1):
            continue
        c.set(px_, py_, tone)


def c_scene():
    c = Canvas(W, H)
    c_sky(c)
    # the sun, low and off to the right, with an ordered-dither halo
    sx, sy = 303, 85
    for y in range(sy - 22, sy + 12):
        for x in range(sx - 26, W):
            d = math.hypot(x + .5 - sx, (y + .5 - sy) * 1.25)
            if d <= 9:
                c.set(x, y, C['sun'])
            elif d < 24 and (24 - d) / 15 > (BAYER[y % 4][x % 4] + .5) / 16:
                c.set(x, y, C['s6'])
    for x, y, rx, ry in ((66, 30, 34, 3), (92, 36, 22, 2), (214, 50, 40, 3.4), (250, 56, 20, 2), (150, 18, 26, 2.2),
                         (24, 62, 26, 2.4)):
        streak(c, x, y, rx, ry)
    hills(c, C['far'], 22, 5, r=(30, 52))
    hills(c, C['mid'], 13, 9, r=(18, 30))
    # the treeline: dark against the glow, rim-lit on the sun side
    g = random.Random(21)
    items, x = [], -4
    while x < W + 4:
        items.append((x, 96 - g.randint(2, 7), g.choice((4, 5, 5, 6, 7)))); x += g.randint(5, 9)
    g.shuffle(items)
    for x, cy, rad in items:
        if 120 <= x <= 200:
            continue
        for px_, py_, nx, ny in m_ellipse(x, cy, rad, rad):
            if py_ < 96:
                l = nx * C_LIGHT[0] + ny * C_LIGHT[1]
                c.set(px_, py_, C['treeRim'] if l > 0.8 else (P['wall'] if l > 0.15 else C['treeD']))
    # the water tower, a silhouette with one lit edge
    t = Sprite(24, 30, 12, 29, light=C_LIGHT, cuts=(0.45, -0.2))
    t.part(m_ellipse(0, -18, 8.5, 6.5), [C['greyDD'], C['greyD'], C['grey'], C['s6']])
    t.part(m_poly([(-6, -24), (0, -28), (6, -24)]), [C['greyDD'], C['greyDD'], C['greyD'], C['s6']])
    for lx in (-6, 5):
        t.part(m_poly([(lx, -12), (lx + 2, -12), (lx + 2, 0), (lx, 0)]), C['greyDD'])
    t.lstamp(["K.........K", ".KK.....KK.", "...KK.KK...", ".....K.....", "...KK.KK...", ".KK.....KK."],
             {'K': C['greyDD']}, -5, -9)
    c.blit(t, 248 - t.ox, 96 - t.oy)
    for x in (40, 280):
        c.rect(x, 96 - 28, 1, 28, C['poleD']); c.rect(x + 1, 96 - 28, 1, 28, C['poleL'])
        c.rect(x - 1, 96 - 30, 4, 2, P['score'])
    # the wall: padded panels, shaded to its foot by ordered dither
    c.rect(0, 96, W, 8, P['wall'])
    c.rect(0, 97, W, 1, C['wallL'])
    bayer_gradient(c, 0, 98, W, 6, P['wall'], C['wallD'])
    for x in range(10, W, 20):
        c.rect(x, 97, 1, 7, C['wallD'])
    c.rect(0, 96, W, 1, P['score'])
    # the track in the wall's shadow, the grass mown to a checkerboard in perspective
    c.rect(0, 104, W, 4, P['dirt'])
    bayer_gradient(c, 0, 104, W, 3, C['dirtDD'], P['dirt'])
    y, hs = 108, (3, 3, 4, 4, 5, 6, 7, 8, 10, 12, 14, 17, 20, 24)
    for i, h in enumerate(hs):
        for yy in range(y, min(H, y + h)):
            for x in range(W):
                k = math.floor((x + .5 - 160) / (46 * (yy - 92) / (H - 92)) + 0.5) if yy > 120 else 0
                c.set(x, yy, P['grassA'] if (i + k) % 2 else P['grassB'])
        y += h
    # the board: a dark face, a frame that catches the sun on one side
    c.rect(125, 77, 70, 19, C['greyDD'])
    c.rect(193, 77, 2, 19, C['s6'])
    c.rect(125, 77, 70, 1, C['greyD'])
    c.rect(128, 80, 64, 16, INK)
    c.t3(134, 84, now.FEET, P['score'])
    c.t3(134, 91, now.PARK, P['chalk'])
    for i in range(3):
        c.rect(168 + i * 5, 84, 3, 3, P['score'] if i < 1 else C['greyDD'])
    for dx in (6, 55):
        x = 128 + dx
        c.rect(x, 69, 1, 8, C['greyL'])
        for j in range(3):
            c.rect(x + 1, 69 + j, 5 - j, 1, C['red'] if j < 2 else C['redDD'])
    for ex in (40, 280):
        c.line(160, 196, ex, 104, P['chalk'])
        c.line(160 + (1 if ex > 160 else -1), 196, (160 + ex) / 2, 150, P['chalk'])
    # the mound and the plate circle, lit from the right
    c.ellipse(160, 120.5, 16, 5, C['dirtDD'])
    c.ellipse(161, 119.3, 15, 4.2, P['dirtD'])
    c.ellipse(162, 118.8, 13, 3.2, P['dirt'])
    c.ellipse(167, 118, 5, 1.4, C['dirtL'])
    c.rect(157, 117, 6, 1, P['chalk'])
    c.ellipse(160, 205, 94, 25.5, C['dirtDD'])
    c.ellipse(161, 205.4, 93, 24.6, P['dirtD'])
    c.ellipse(163, 206, 90, 23.5, P['dirt'])
    speckle(c, 11, (70, 184, 252, 223), 90, [C['dirtL'], P['dirtD']], P['dirt'])
    for sgn in (-1, 1):
        pts = [(160 + sgn * 22, 189), (160 + sgn * 68, 189), (160 + sgn * 82, 221), (160 + sgn * 26, 221)]
        for i in range(4):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % 4]
            c.line(x0, y0, x1, y1, P['chalk'])
    for j, (x0, x1) in enumerate([(152, 168), (152, 168), (153, 167), (155, 165), (157, 163), (159, 161)]):
        c.rect(x0, 190 + j, x1 - x0, 1, P['chalk'])
        c.px(x0, 190 + j, C['greyL'])
    # long shadows first, then the people
    ps, bs = c_pitcher(2), c_batter(0)
    cast_shadow(c, ps, 160, 117, k=0.9, rise=0.1, soft_from=12)
    cast_shadow(c, bs, 104, 222)
    c.blit(ps, 160 - ps.ox, 117 - ps.oy)
    now.zone(c, P['chalk'])
    c.blit(bs, 104 - bs.ox, 222 - bs.oy)
    bx, by, r = now.BALL
    c.baseball(bx, by, r, C['poleL'])
    c.px(bx - 2, by + 2, C['greyL']); c.px(bx - 1, by + 3, C['greyL']); c.px(bx - 3, by + 1, C['greyL'])
    c.t3(8, H - 12, '87 MPH', P['chalk'], shadow=INK)
    c.t3(8, 8, now.HUD, P['chalk'], shadow=INK)
    return c


# ======================================================================================
# build
# ======================================================================================

def ball_strip(outline=None, highlight=None):
    s = Canvas(46, 12)
    x = 3
    for r in (1, 2, 3, 4):
        s.baseball(x + r, 6, r, highlight or P['sky3'], outline)
        if outline is None and r >= 2:
            s.px(x + 2 * r, 6, P['ink'])
        x += 2 * r + 6
    return s


def row_of(sprites, gap=5):
    trimmed = [sp.trimmed(1) for sp in sprites]
    h = max(t.h for t in trimmed)
    w = sum(t.w for t in trimmed) + gap * (len(trimmed) - 1)
    o = Canvas(w, h)
    x = 0
    for t in trimmed:
        o.blit(t, x, h - t.h)
        x += t.w + gap
    return o


def build(tag, scene, batter, pitcher, ball):
    os.makedirs(OUT, exist_ok=True)
    sc = scene()
    sc.png(os.path.join(OUT, f'{tag}-scene.png'), 4)
    used = dict(sc.used())
    frames = [batter(f) for f in range(3)]
    stance, swings = frames[0].trimmed(1), row_of(frames[1:], 6)
    stance.png(os.path.join(OUT, f'{tag}-batter-stance.png'), 8)
    swings.png(os.path.join(OUT, f'{tag}-batter-swings.png'), 4)
    pf = [pitcher(f) for f in range(3)]
    prow = row_of(pf, 6)
    prow.png(os.path.join(OUT, f'{tag}-pitcher.png'), 8)
    ball.png(os.path.join(OUT, f'{tag}-ball.png'), 8)
    for sp in frames + pf + [ball]:
        for k, v in sp.used().items():
            used[k] = used.get(k, 0) + v
    cols = sorted(used, key=lambda c_: (-used[c_]))
    info = dict(tag=tag, count=len(cols), colours=[hexof(c_) for c_ in cols],
                stance=[stance.w, stance.h], swings=[swings.w, swings.h], pitcher=[prow.w, prow.h])
    with open(os.path.join(OUT, f'{tag}-info.json'), 'w') as f:
        json.dump(info, f, indent=1)
    print(tag, len(cols), 'colours', info['stance'], info['swings'], info['pitcher'])


def blit_scaled(dst, src, x, y, k):
    for j in range(src.h):
        for i in range(src.w):
            c_ = src.p[j][i]
            if c_ is not None:
                dst.rect(x + i * k, y + j * k, k, k, c_)


def sheet(tag, batter, pitcher, ball):
    """One 320x200 sheet at 4x: the stance at 8x, the two swings at 4x, the pitcher at 8x, the ball at 4x."""
    SW, SH = 320, 200
    s = Canvas(SW, SH)
    s.rect(0, 0, SW, SH, P['grassA'])
    for y in range(0, SH, 24):
        s.rect(0, y, SW, 12, P['grassB'])
    ink = P['ink']
    frames = [batter(f).trimmed(1) for f in range(3)]
    hero = frames[0]
    blit_scaled(s, hero, 10, 194 - hero.h * 2, 2)
    s.t3(10, 5, 'STANCE  8X', P['chalk'], shadow=ink)
    x = 128
    for name, fr in (('CONTACT  4X', frames[1]), ('MISS', frames[2])):
        s.blit(fr, x, 98 - fr.h)
        s.t3(x + (0 if name != 'MISS' else fr.w - 18), 5 if name != 'MISS' else 5, name, P['chalk'], shadow=ink)
        x += fr.w + 8
    px_ = 128
    for name, f in (('SET', 0), ('KICK', 1), ('RELEASE', 2)):
        sp = pitcher(f).trimmed(1)
        blit_scaled(s, sp, px_, 194 - sp.h * 2, 2)
        s.t3(px_, 132, name, P['chalk'], shadow=ink)
        px_ += sp.w * 2 + 10
    s.blit(ball, SW - ball.w - 4, 194 - ball.h)
    s.t3(SW - ball.w - 2, 172, 'BALL  4X', P['chalk'], shadow=ink)
    s.png(os.path.join(OUT, f'{tag}-sheet.png'), 4)


SHEETS = {
    'now': lambda: sheet('now', now.batter_sprite, now.pitcher_sprite, ball_strip()),
    'a': lambda: sheet('a', a_batter, a_pitcher, ball_strip()),
    'b': lambda: sheet('b', b_batter, b_pitcher, ball_strip(outline=P['ink'])),
    'c': lambda: sheet('c', c_batter, c_pitcher, ball_strip(highlight=C['poleL'])),
}

VARIANTS = {
    'now': lambda: build('now', now.scene, now.batter_sprite, now.pitcher_sprite, ball_strip()),
    'a': lambda: build('a', a_scene, a_batter, a_pitcher, ball_strip()),
    'b': lambda: build('b', b_scene, b_batter, b_pitcher, ball_strip(outline=P['ink'])),
    'c': lambda: build('c', c_scene, c_batter, c_pitcher, ball_strip(highlight=C['poleL'])),
}

if __name__ == '__main__':
    for v in (sys.argv[1:] or list(VARIANTS)):
        VARIANTS[v]()
        SHEETS[v]()
