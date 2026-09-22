"""Round two of C (Golden Hour): the look as a lighting scheme — dusk, night, day — with more
detail squeezed out of the people and PARK 12's real stands behind the wall.
python3 golden.py"""
import os, sys, json
from engine import *
import now as NOW
import variants as V
import side as S

W, H = 320, 224
INK = P['ink']
OUT = V.OUT

F5 = {
    "0": "01110100011000110001100011000101110", "1": "00100011000010000100001000010001110",
    "2": "01110100010000100010001000100011111", "3": "11111000100010000010000011000101110",
    "4": "00010001100101010010111110001000010", "5": "11111100001111000001000011000101110",
    "6": "00110010001000011110100011000101110", "7": "11111000010001000100010000100001000",
    "8": "01110100011000101110100011000101110", "9": "01110100011000101111000010001001100",
    "F": "11111100001000011110100001000010000", "T": "11111001000010000100001000010000100",
    "H": "10001100011000111111100011000110001", "R": "11110100011000111110101001001010001",
    " ": "00000000000000000000000000000000000", "B": "11110100011000111110100011000111110",
    "A": "01110100011000111111100011000110001", "E": "11111100001000011110100001000011111",
    "L": "10000100001000010000100001000011111",
}


def t5(c, x, y, text, colour, scale=1, shadow=None):
    if shadow is not None:
        t5(c, x + 1, y + 1, text, shadow, scale)
    cx = x
    for ch in text.upper():
        bits = F5.get(ch, F5[" "])
        for j in range(7):
            for i in range(5):
                if bits[j * 5 + i] == "1":
                    c.rect(cx + i * scale, y + j * scale, scale, scale, colour)
        cx += 6 * scale


def L(**kw):
    out = {}
    for k, v in kw.items():
        if isinstance(v, str) and v.startswith('#'):
            out[k] = col(v)
        elif isinstance(v, (list, tuple)) and v and isinstance(v[0], str) and v[0].startswith('#'):
            out[k] = [col(h) for h in v]
        elif k == 'sky':
            out[k] = [(y, col(h)) for y, h in v]
        else:
            out[k] = v
    return out


DUSK = L(name='dusk',
         sky=[(0, '#222266'), (8, '#222266'), (22, '#444488'), (28, '#444488'), (42, '#6666AA'), (46, '#6666AA'),
              (58, '#AA88AA'), (61, '#AA88AA'), (70, '#CC8888'), (73, '#CC8888'), (81, '#EEAA88'), (84, '#EEAA88'),
              (92, '#EECC88'), (96, '#EECC88')],
         cloud=['#AA88AA', '#CC8888', '#EEAA88', '#EECC88'], sun=['#EEEEAA', '#EECC88'], sun_at=(27, 63, 9, 27),
         hill=['#886688', '#664466'], tree=['#224444', '#226644', '#CCAA66'], light=(-0.85, -0.5),
         stand_lit=['#666688', '#EECC88', '#444466'], stand_dim=['#444466', '#886688', '#222244'],
         heads_lit=['#EEAA88', '#EECCAA', '#CC8866'],
         shirts_lit=['#CC2222', '#EE8866', '#AAAACC', '#CC8888', '#EECC88', '#8888AA', '#6666AA'],
         heads_dim=['#884444', '#CC8866'], shirts_dim=['#660022', '#444488', '#666688', '#6666AA', '#664466'],
         deck=['#664466', '#EECC88', '#EEEEAA', '#444466'], wall=['#44AA66', '#226644', '#004422'],
         grass_sun='#66AA44', dirt=['#EEAA66', '#CC8844', '#AA6622', '#884422'],
         red=['#660022', '#AA2222', '#CC2222', '#EE8866'], grey=['#444466', '#666688', '#8888AA', '#CCAAAA'],
         skin=['#884444', '#CC8866', '#EEAA88', '#EECCAA'], wood=['#442222', '#884422', '#AA8844', '#EECC88'],
         glove=['#666688', '#AAAACC', '#EEEEEE', '#EEEEEE'], hair='#442222',
         pole=['#EEEE88', '#CCAA22'], board=['#444466', '#EECC88', '#222244'], ball_hi='#EEEE88', ball_lo='#AAAACC',
         shadows=[(-0.9, 0.22, 62)], cuts=(0.3, -0.35))

NIGHT = L(name='night',
          sky=[(0, '#000022'), (34, '#000022'), (54, '#222244'), (62, '#222244'), (84, '#222266'), (90, '#222266'),
               (96, '#444488')],
          cloud=['#666688', '#444488', '#444466', '#222244'], sun=['#EEEECC', '#444488'], sun_at=(262, 26, 7, 17),
          hill=['#222244', '#000022'], tree=['#002222', '#224444', '#446666'], light=(-0.3, -0.95),
          stand_lit=['#444466', '#AAAACC', '#222244'], stand_dim=['#444466', '#AAAACC', '#222244'],
          heads_lit=['#EEAA88', '#EECCAA', '#CC8866'],
          shirts_lit=['#CC2222', '#AAAACC', '#EEEEEE', '#4466CC', '#EEDD22', '#666688', '#EE6666'],
          heads_dim=['#EEAA88', '#EECCAA', '#CC8866'],
          shirts_dim=['#CC2222', '#AAAACC', '#EEEEEE', '#4466CC', '#EEDD22', '#666688', '#EE6666'],
          deck=['#222244', '#AAAACC', '#EEEEAA', '#222244'], wall=['#44AA66', '#226644', '#004422'],
          grass_sun=None, dirt=['#EEAA66', '#CC8844', '#AA6622', '#884422'],
          red=['#660022', '#AA2222', '#CC2222', '#EE6666'], grey=['#444466', '#8888AA', '#AAAACC', '#EEEEEE'],
          skin=['#884444', '#CC8866', '#EEAA88', '#EECCAA'], wood=['#442222', '#884422', '#AA8844', '#EECC88'],
          glove=['#666688', '#AAAACC', '#EEEEEE', '#EEEEEE'], hair='#442222',
          pole=['#EEEE88', '#CCAA22'], board=['#222244', '#AAAACC', '#000022'], ball_hi='#EEEEEE', ball_lo='#AAAACC',
          shadows=[(-0.34, 0.1, 99), (0.34, 0.1, 99)], cuts=(0.35, -0.4))

DAY = L(name='day',
        sky=[(0, '#4466CC'), (30, '#4466CC'), (50, '#66AAEE'), (60, '#66AAEE'), (78, '#AACCEE'), (86, '#AACCEE'),
             (96, '#CCEEEE')],
        cloud=['#EEEEEE', '#EEEEEE', '#AACCEE', '#88AACC'], sun=None, sun_at=None,
        hill=['#88AACC', '#66AA88'], tree=['#116633', '#228844', '#66CC44'], light=(-0.6, -0.8),
        stand_lit=['#666688', '#EEEEEE', '#444466'], stand_dim=['#666688', '#EEEEEE', '#444466'],
        heads_lit=['#EEAA88', '#EECCAA', '#CC8866', '#884422'],
        shirts_lit=['#CC2222', '#EEEEEE', '#4466CC', '#EEDD22', '#66CC44', '#EE6666', '#AAAACC'],
        heads_dim=['#EEAA88', '#EECCAA', '#CC8866', '#884422'],
        shirts_dim=['#CC2222', '#EEEEEE', '#4466CC', '#EEDD22', '#66CC44', '#EE6666', '#AAAACC'],
        deck=['#8888AA', '#EEEEEE', '#66AAEE', '#666688'], wall=['#44AA66', '#226644', '#004422'],
        grass_sun=None, dirt=['#EEAA66', '#CC8844', '#AA6622', '#884422'],
        red=['#880022', '#AA2222', '#CC2222', '#EE6666'], grey=['#666688', '#8888AA', '#AAAACC', '#EEEEEE'],
        skin=['#AA6644', '#CC8866', '#EEAA88', '#EECCAA'], wood=['#664422', '#AA6622', '#CC8844', '#EECC88'],
        glove=['#8888AA', '#AAAACC', '#EEEEEE', '#EEEEEE'], hair='#442222',
        pole=['#EEEE88', '#CCAA22'], board=['#444466', '#EEEEEE', '#222244'], ball_hi='#EEEEEE', ball_lo='#AAAACC',
        shadows=[(-0.3, 0.12, 99)], cuts=(0.35, -0.3))


# ======================================================================================
# The people, with the detail squeezed out
# ======================================================================================

def POSE(**kw):
    """One pose of the three-quarter rig. R = his right = back = near (drawn in front)."""
    d = dict(aR=(-8, -3), aL=(6, -12), kR=(0, -17), kL=(9, -24), hipR=(-3, -31), hipL=(4, -34),
             shR=(-5, -50), shL=(6, -54), elR=(-15, -50), elL=None, hd=(-8, -55), tip=(-22, -86),
             bat_front=True, bat_over_arms=False, heelR=False, opened=0.0, far_arm='cap',
             torso=[(-10, -51), (-4, -56), (5, -57), (10, -53), (9, -44), (7, -30), (-6, -30), (-10, -42)],
             number=(-7, -44), buckle=(6, -32), head='back')
    d.update(kw)
    return d


STANCE = POSE()
SWING = POSE(kR=(0, -17), hipR=(-2, -30), shR=(-4, -50), shL=(7, -54), elR=(-9, -44), hd=(0, -46),
             tip=(-34, -52), bat_front=False, heelR=False)


def contact_pose(degrees):
    """The bat lies along the slice at contact; the hands slide out and down as the swing steepens."""
    s = (degrees - 20) / 50.0
    hd = (17 + 2 * s, -44 + 10 * s)
    a = math.radians(degrees)
    tip = (hd[0] + 44 * math.cos(a), hd[1] - 44 * math.sin(a))
    shR, shL = (-4, -51), (8, -54)
    elR = (shR[0] + (hd[0] - shR[0]) * 0.5 + 1, shR[1] + (hd[1] - shR[1]) * 0.5 + 2)
    elL = (shL[0] + (hd[0] - shL[0]) * 0.5, shL[1] + (hd[1] - shL[1]) * 0.5 - 2)
    return POSE(aR=(-7, -3), aL=(6, -12), kR=(2, -18), kL=(8, -24), hipR=(-1, -31), hipL=(5, -34),
                shR=shR, shL=shL, elR=elR, elL=elL, hd=hd, tip=tip, bat_front=False, heelR=True, opened=1,
                far_arm='full',
                torso=[(-9, -52), (-2, -57), (7, -57), (11, -52), (10, -44), (8, -30), (-6, -30), (-9, -42)],
                number=(-3, -44), buckle=(8, -32))


def finish_pose(degrees):
    """The follow-through: the bat's finish angle rises with the slice."""
    phi = math.radians(52 + (degrees - 20) * 0.6)
    hd = (-8, -56)
    tip = (hd[0] - 30 * math.cos(phi), hd[1] - 30 * math.sin(phi))
    return POSE(aR=(-6, -3), aL=(6, -12), kR=(1, -18), kL=(7, -24), hipR=(-2, -31), hipL=(5, -34),
                shR=(8, -53), shL=(-6, -52), elR=(0, -49), elL=None, hd=hd, tip=tip, bat_front=True, heelR=True,
                opened=1, far_arm='cap',
                torso=[(-9, -53), (-2, -57), (7, -57), (11, -53), (10, -44), (8, -30), (-6, -30), (-9, -42)],
                number=(-2, -44), buckle=(9, -32), head='back')


def pose_for(frame, degrees=20):
    """stance, contact, finish, swing — the frame numbers `at_bat` and the Swift port use."""
    return {0: STANCE, 1: contact_pose(degrees), 2: finish_pose(degrees), 3: SWING}[frame]


def batter_ground(frame, degrees=20):
    """The ground line under a pose for `cast`: from the back foot up to the front foot."""
    p = pose_for(frame, degrees)
    return (p['aR'][0], p['aL'][0], p['aR'][1] - p['aL'][1])


def batter(frame, look, degrees=20):
    p = pose_for(frame, degrees)
    s = Sprite(128, 104, 50, 100, look['light'], look['cuts'], inner=True)
    red, grey, skin, wood = look['red'], look['grey'], look['skin'], look['wood']
    shoe = [INK, INK, grey[0], grey[2]]

    def leg(hip, knee, ank, heel):
        ax, ay = ank
        if heel:                                                   # up on the toe, pivoting
            s.part(m_capsule(ax + 5, ay + 1.5, 2.0, ax - 2, ay - 1.5, 2.4), shoe, INK)
        else:
            s.part(m_ellipse(ax + 1.5, ay + 2, 5.8, 2.5), shoe, INK)
            s.lset(ax + 5, ay + 1, grey[2])
        s.part(m_capsule(knee[0], knee[1], 3.6, ax, ay, 2.7), red, red[0])
        mid = ((knee[0] + ax) / 2, (knee[1] + ay) / 2 - 1)
        s.part(m_capsule(knee[0], knee[1], 4.0, mid[0], mid[1], 3.3), grey, grey[0])
        s.part(m_capsule(hip[0], hip[1], 5.3, knee[0], knee[1], 4.1), grey, grey[0])
        s.line(hip[0] + s.ox, hip[1] + s.oy + 2, knee[0] + s.ox, knee[1] + s.oy, red[1])
        s.line(knee[0] + s.ox, knee[1] + s.oy, mid[0] + s.ox, mid[1] + s.oy, red[1])
        s.lset(knee[0] - 3, knee[1] - 1, grey[0]); s.lset(knee[0] - 2, knee[1], grey[0])

    leg(p['hipL'], p['kL'], p['aL'], False)                        # the front leg is the far one
    leg(p['hipR'], p['kR'], p['aR'], p['heelR'])
    # the hips: a seat across both thigh tops so the two legs read as one pelvis
    s.part(m_ellipse((p['hipL'][0] + p['hipR'][0]) / 2, (p['hipL'][1] + p['hipR'][1]) / 2 + 1, 8.0, 3.4), grey, grey[0])

    def sleeve(a, b, r0=3.4, r1=2.8):
        s.part(m_capsule(a[0], a[1], r0, b[0], b[1], r1), red, red[0])

    def forearm(a, b):
        s.part(m_capsule(a[0], a[1], 2.8, b[0], b[1] + 1, 2.3), skin, skin[0])
        wx, wy = a[0] + (b[0] - a[0]) * 0.72, a[1] + (b[1] + 1 - a[1]) * 0.72
        s.part(m_ellipse(wx, wy, 2.4, 1.6), red[1], None)

    if p['far_arm'] == 'hidden_reach':                              # behind the torso, only the tip shows
        sleeve(p['shL'], p['hd'])
    s.part(m_poly(p['torso']), grey, grey[0])
    s.part(m_ellipse(0.5, -53, 9.0, 3.8), grey, None)
    s.part(m_poly([(-7.5, -33), (8.5, -33), (8.5, -30), (-7.5, -30)]), INK, None)
    s.lset(p['buckle'][0], p['buckle'][1], P['score']); s.lset(p['buckle'][0] + 1, p['buckle'][1], P['score'])
    s.lstamp(["RRR", "..R", ".R.", ".R.", ".R."], {'R': red[1]}, p['number'][0], p['number'][1])
    if p['far_arm'] == 'full' and p['elL']:
        sleeve(p['shL'], p['elL'], 3.2, 2.7); forearm(p['elL'], (p['hd'][0], p['hd'][1] - 2))
    else:                                                          # just the shoulder cap of the front arm
        s.part(m_ellipse(p['shL'][0], p['shL'][1] + 1, 3.4, 3.0), red, red[0])

    hx, hy, tx, ty = p['hd'][0], p['hd'][1] + 2, p['tip'][0], p['tip'][1]

    def bat():
        V.bat_part(s, hx, hy, tx, ty, dict(bat=wood, line_bat=wood[0]), 1.0, 2.6)
        for u in (0.12, 0.16, 0.2, 0.24, 0.28, 0.32):
            bx_, by_ = hx + (tx - hx) * u, hy + (ty - hy) * u
            s.lset(round(bx_ - .5), round(by_ - .5), wood[0]); s.lset(round(bx_ + .5), round(by_ - .5), wood[0])

    if not p['bat_front']:
        bat()

    # the head from behind and to the right: the nape, the helmet with its brim toward the
    # pitcher (up and right), his right ear and a sliver of cheek on the near side
    s.part(m_poly([(0, -58), (5, -58), (5, -54), (0, -54)]), skin, None)
    s.part(m_ellipse(3, -61.5, 5.2, 5.6), skin, skin[0])
    s.lset(0, -57, look['hair']); s.lset(1, -57, look['hair']); s.lset(0, -56, look['hair']); s.lset(2, -57, look['hair'])
    s.part([q for q in m_ellipse(2, -63, 7, 6.2) if q[1] < -59], red, red[0])
    s.part(m_poly([(-4, -61), (1, -61), (1, -57), (-3, -57), (-4, -59)]), red, red[0])   # the helmet's back-left edge
    s.part(m_poly([(5, -61), (10, -61), (10, -57), (7, -57)]), red, red[0])            # ...and its right side, over the ear
    s.part(m_poly([(7, -67), (14, -66), (14, -64), (8, -64)]), red[1], None)             # the brim, toward the pitcher
    s.lset(7, -59, skin[1]); s.lset(8, -59, skin[0]); s.lset(7, -58, skin[1])             # his right ear, and the cheek below it
    s.lset(9, -58, skin[2]); s.lset(9, -57, skin[1])
    s.lset(-2, -67, skin[3]); s.lset(-3, -66, skin[3]); s.lset(-1, -68, skin[3])           # the glint
    if p['bat_front']:
        bat()

    sleeve(p['shR'], p['elR'])
    forearm(p['elR'], p['hd'])
    s.part(m_ellipse(p['hd'][0], p['hd'][1], 2.8, 3.3), look['glove'], look['glove'][0])
    return s


PITCH = {
    0: ["....RRR....",
        "...HRRRr...",
        "...RRRRr...",
        "...rrrrrr..",
        "...SSSSs...",
        "...SKSKs...",
        "....SSs....",
        "..WLUUUUu..",
        ".WLUUNUUUu.",
        ".WLUGGGUUu.",
        ".SLUGGgUus.",
        "..LUGggUu..",
        "..LUUUUUu..",
        "..KKKKKKK..",
        "..WLUuLUu..",
        "..WLU.LUu..",
        "..WLU.LUu..",
        "..HRr.HRr..",
        "..HRr.HRr..",
        ".KKKK.KKKK."],
    1: ["....RRR......S.",
        "...HRRRr....SB.",
        "...RRRRr...LU..",
        "...rrrrrr.LU...",
        "...SSSSs.LU....",
        "...SKSKsLU.....",
        "....SSs.U......",
        ".GWLUUUUu......",
        "GGGLUUNUu......",
        "GgWLUUUUu......",
        ".g.LUUUUUUu....",
        "...LUUUUULUUu..",
        "...KKKKKK.LUu..",
        "...WLUu...LUu..",
        "...WLUu...HRr..",
        "...WLUu...HRr..",
        "...WLUu...KKKK.",
        "...HRr.........",
        "...HRr.........",
        "..KKKK........."],
    2: [".....RRR.......",
        "....HRRRr......",
        "....RRRRr......",
        "....rrrrrr.....",
        "....SSSSs......",
        "....SKSKs......",
        ".....SSs.......",
        ".G.WLUUUUUu....",
        "GGGLUUNUUULUu..",
        "Gg.LUUUUUu.LUS.",
        ".g.LUUUUUu..SS.",
        "...LUUUUUu.....",
        "...KKKKKKK.....",
        "..WLUu.LUUu....",
        ".WLUu...LUUu...",
        ".WLu.....LUu...",
        ".HRr.....HRr...",
        ".HRr.....HRr...",
        "KKKK.....KKKK.."],
}


def pitcher(frame, look):
    rows = PITCH[frame]
    s = Sprite(44, 44, 16, 40)
    red, grey, skin, wood = look['red'], look['grey'], look['skin'], look['wood']
    leg = {'R': red[2], 'r': red[0], 'H': red[3], 'S': skin[2], 's': skin[1], 'U': grey[2], 'u': grey[0],
           'L': grey[2] if look['name'] == 'night' else grey[3], 'W': grey[3], 'K': INK, 'G': wood[1], 'g': wood[0],
           'B': P['chalk'], 'N': red[1]}
    s.lstamp(rows, leg, -5, -len(rows))
    return s


# ======================================================================================
# The at-bat camera
# ======================================================================================

def sky(c, look, bottom=96, stretch=1.0):
    stops = [(round(y * stretch), h) for y, h in look['sky']]
    stops[-1] = (int(bottom), stops[-1][1])
    for (y0, a), (y1, b) in zip(stops, stops[1:]):
        if y1 <= y0:
            continue
        if a == b:
            c.rect(0, y0, W, y1 - y0, a)
        else:
            bayer_gradient(c, 0, y0, W, y1 - y0, a, b)


def sun(c, look, at=None, clip_y=None):
    if not look['sun']:
        return
    sx, sy, r, halo = at or look['sun_at']
    disc, glow = look['sun']
    for y in range(int(sy - halo), int(sy + halo)):
        if clip_y is not None and y >= clip_y:
            break
        for x in range(int(sx - halo * 1.3), int(sx + halo * 1.3)):
            d = math.hypot(x + .5 - sx, (y + .5 - sy) * 1.2)
            if d <= r:
                c.set(x, y, disc)
            elif d < halo and (halo - d) / (halo - r) * 0.95 > (BAYER[y % 4][x % 4] + .5) / 16:
                c.set(x, y, glow)
    if look['name'] == 'night':                       # the bite out of the moon
        for px_, py_, _, _ in m_ellipse(sx + r * 0.62, sy - 1, r * 0.82, r * 0.82):
            if math.hypot(px_ + .5 - sx, py_ + .5 - sy) <= r:
                c.set(px_, py_, look['sky'][0][1])


def stars(c, seed, y_max, n=70):
    g = random.Random(seed)
    for _ in range(n):
        x, y = g.randint(0, W - 1), int(y_max * g.random() ** 1.6)
        c.set(x, y, P['chalk'] if g.random() < 0.35 else col('#AAAACC'))
        if g.random() < 0.08:
            for ax, ay in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                c.set(x + ax, y + ay, col('#666688'))


def clouds(c, look, spots):
    t = look['cloud']
    for x, y, rx, ry in spots:
        if look['name'] == 'day':
            own = {}
            for dx, r in ((-rx * .5, ry * 1.6), (-rx * .1, ry * 2.6), (rx * .3, ry * 2.0), (rx * .62, ry * 1.2)):
                for px_, py_, nx, ny in m_ellipse(x + dx, y - r * 0.6, r, r):
                    if py_ < y:
                        own[(px_, py_)] = (nx, ny)
            for (px_, py_), (nx, ny) in own.items():
                l = nx * -0.6 + ny * -0.8
                c.set(px_, py_, t[3] if py_ >= y - 1 else (t[2] if (l < -0.35 or py_ >= y - 3) else t[0]))
        else:
            for px_, py_, nx, ny in m_ellipse(x, y, rx, ry):
                tone = t[0] if ny < -0.35 else (t[3] if (ny > 0.45 and nx > -0.5) else (t[2] if ny > 0.05 else t[1]))
                if abs(nx) > 0.78 and ((px_ + py_) & 1):
                    continue
                c.set(px_, py_, tone)


def leafy(c, look, x0, x1, baseline, seed):
    g = random.Random(seed)
    lx, ly = look['light']
    items, x = [], x0 - 3
    while x < x1:
        items.append((x, baseline - g.randint(2, 7), g.choice((4, 5, 5, 6, 7)))); x += g.randint(5, 9)
    g.shuffle(items)
    t = look['tree']
    for x, cy, rad in items:
        for px_, py_, nx, ny in m_ellipse(x, cy, rad, rad):
            if py_ < baseline and x0 <= px_ < x1:
                l = nx * lx + ny * ly
                c.set(px_, py_, t[2] if l > 0.75 else (t[1] if l > 0.1 else t[0]))


TIERS = {'full': (82, 10), 'bleachers': (88, 7), 'lowBleacher': (92, 3)}   # top beside the board, two-pixel steps to the edge


def wing_top(x, tier='full'):
    d = (124 - x) / 124 if x < 160 else (x - 196) / 124
    top, steps = TIERS[tier]
    return top - int(max(0, min(1, d)) * steps) * 2


def wing(c, look, side, seed):
    lit = side > 0 or look['name'] != 'dusk'
    mass, lip, under = look['stand_lit'] if lit else look['stand_dim']
    heads = look['heads_lit'] if lit else look['heads_dim']
    shirts = look['shirts_lit'] if lit else look['shirts_dim']
    deck_mass, roof, lamp, column = look['deck']
    xs = range(0, 124) if side < 0 else range(196, W)
    g = random.Random(seed)
    for x in xs:
        top = wing_top(x)
        c.rect(x, top, 1, 96 - top, mass)
        c.rect(x, top + 2, 1, 5, deck_mass)                     # the upper deck's fascia
        c.set(x, top, roof if (lit or look['name'] == 'dusk') else under); c.set(x, top + 1, under)
        if x % 6 == 2:
            c.set(x, top + 4, lamp); c.set(x + 1, top + 4, lamp)
        if x % 17 == 5:
            c.rect(x, top + 7, 1, 3, column)
        for k in (1, 2):                                        # the tiers' lips
            yy = 96 - 9 * k
            if yy > top + 10:
                c.set(x, yy, lip)
    row, y = 0, 94
    while y > 64:
        for x in xs:
            if (x + row) % 2 or y - 1 <= wing_top(x) + 10 or (96 - y) % 9 == 0 or (96 - (y - 1)) % 9 == 0:
                continue
            if x % 23 == 11:                                    # an aisle
                c.set(x, y, under); c.set(x, y - 1, under); continue
            if g.random() < 0.88:
                c.set(x, y - 1, g.choice(heads)); c.set(x, y, g.choice(shirts))
        y -= 3; row += 1
    edge = 123 if side < 0 else 196
    c.rect(edge, wing_top(edge), 1, 96 - wing_top(edge), under)


def towers(c, look, slots=(62, 96, 224, 258), foot=96, height=34):
    for n, x in enumerate(slots):
        top = foot - height - (6 if n >= 2 else 0) * 0
        for y in range(int(top + 6), foot):
            t = (y - top) / height
            half = 1 + t * 2.5
            c.set(int(x - half), y, col('#446688')); c.set(int(x + half), y, col('#446688'))
            if (y - top) % 7 == 0:
                c.rect(x - half, y, half * 2 + 1, 1, col('#446688'))
            elif (y - top) % 7 == 3:
                c.set(int(x - half + ((y * 3) % max(1, int(half * 2)))), y, col('#446688'))
        bx, by = x - 7, top - 2
        lit = look['towers']                                # the lamps are on in twilight and at night only
        for yy in range(int(by - 8), int(by + 14)):
            for xx in range(int(bx - 9), int(bx + 24)):
                d = math.hypot((xx - (bx + 7)) / 15, (yy - (by + 3)) / 9)
                if lit and d < 1 and (1 - d) * 0.9 > (BAYER[yy % 4][xx % 4] + .5) / 16:
                    c.set(xx, yy, col('#444488') if d > 0.55 else col('#6666AA'))
        c.rect(bx - 1, by - 1, 17, 9, INK)
        for j in range(2):
            for i in range(4):                              # a dark bank keeps its lamps in the pole colour
                c.rect(bx + i * 4, by + j * 4, 3, 3, col('#EEEEAA') if lit else col('#446688'))
                if lit:
                    c.px(bx + i * 4 + 1, by + j * 4 + 1, P['chalk'])


def cast(c, sp, fx, fy, look, table, ground=None):
    """`ground` = (x0, x1, rise): the ground under the figure rises `rise` rows from column x0 to
    column x1, so a front foot drawn higher on the screen is read as deeper, not as in the air."""
    hit = set()
    for k, rise, soft in look['shadows']:
        for y in range(sp.h):
            for x in range(sp.w):
                if sp.p[y][x] is None:
                    continue
                lx, hgt = x - sp.ox, sp.oy - y
                g = 0
                if ground:
                    x0, x1, gr = ground
                    g = gr * max(0, min(1, (lx - x0) / (x1 - x0)))
                    hgt = max(0, hgt - g)
                sx, sy = int(fx + lx - hgt * k), int(fy - g - hgt * rise)
                if hgt > soft and ((sx + sy) & 1):
                    continue
                hit.add((sx, sy))
    for sx, sy in hit:
        base = c.get(sx, sy)
        if base in table:
            c.set(sx, sy, table[base])


def contact_fx(c, look, ball=(172, 158), r=4, degrees=27, power=98, zone_bottom=186):
    a = math.radians(degrees)
    dx, dy = math.cos(a), -math.sin(a)
    pts = [(ball[0] + dx * (-40 + 44 * i / 17), ball[1] + dy * (-40 + 44 * i / 17)) for i in range(18)]
    for p0, p1 in zip(pts, pts[1:]):
        c.line(p0[0], p0[1], p1[0], p1[1], P['chalk'])
    x0, y0, x1, y1 = ball[0] - dx * 16, ball[1] - dy * 16, ball[0] + dx * 16, ball[1] + dy * 16
    c.line(x0, y0, x1, y1, P['chalk'], 3); c.line(x0, y0, x1, y1, P['score'], 1)
    c.baseball(ball[0], ball[1], max(2, r), look['ball_hi'])
    for n in range(8):
        ang = n / 8 * 2 * math.pi + 0.39
        ln = (4 if n % 2 else 8) + 5
        c.line(ball[0] + math.cos(ang) * 10, ball[1] + math.sin(ang) * 10,
               ball[0] + math.cos(ang) * (10 + ln), ball[1] + math.sin(ang) * (10 + ln), P['chalk'])
    label = 'SWING %d  POWER %d' % (degrees, power)
    lx = max(4, min(320 - len(label) * 4 - 4, ball[0] - len(label) * 2)); ly = max(4, min(224 - 24, ball[1] + 18))
    c.rect(lx - 2, ly - 2, len(label) * 4 + 3, 9, INK); c.t3(lx, ly, label, P['score'])
    bw = 6 * 6
    blx, bly = max(4, min(320 - bw - 4, ball[0] - bw / 2)), min(224 - 11, max(zone_bottom + 6, ly + 12))
    c.rect(blx - 2, bly - 2, bw + 3, 11, INK); t5(c, blx, bly, 'BARREL', P['score'])


def at_bat(look, beat='pitch'):
    c = Canvas(W, H)
    night, dusk = look['name'] == 'night', look['name'] == 'dusk'
    sky(c, look)
    if night:
        stars(c, 5, 70)
    sun(c, look)
    clouds(c, look, {'dusk': ((150, 22, 30, 2.4), (214, 40, 36, 3.2), (96, 46, 22, 2), (270, 52, 20, 2)),
                     'night': ((120, 40, 34, 3), (200, 58, 26, 2.2)),
                     'day': ((60, 40, 22, 4), (214, 34, 26, 5), (150, 58, 16, 3))}[look['name']])
    # beyond centre field, through the gap the scoreboard stands in
    V.hills(c, look['hill'][0], 20, 5, r=(30, 52)); V.hills(c, look['hill'][1], 12, 9, r=(18, 30))
    leafy(c, look, 118, 202, 96, 21)
    if night:
        towers(c, look)
    wing(c, look, -1, 3); wing(c, look, +1, 4)
    lit, dark = look['pole'] if look['light'][0] < 0 else look['pole'][::-1]
    for x in (40, 280):
        c.rect(x, 96 - 28, 1, 28, lit); c.rect(x + 1, 96 - 28, 1, 28, dark); c.rect(x - 1, 96 - 30, 4, 2, P['score'])
    # the wall
    wl, wm, wd = look['wall']
    c.rect(0, 96, W, 8, wm); c.rect(0, 97, W, 1, wl)
    bayer_gradient(c, 0, 98, W, 6, wm, wd)
    for x in range(10, W, 20):
        c.rect(x, 97, 1, 7, wd)
    c.rect(0, 96, W, 1, P['score'])
    # the track, then the grass mown to a checkerboard in perspective
    d_l, d_m, d_d, d_dd = look['dirt']
    c.rect(0, 104, W, 4, d_m); bayer_gradient(c, 0, 104, W, 3, d_dd, d_m)
    y, hs = 108, (3, 3, 4, 4, 5, 6, 7, 8, 10, 12, 14, 17, 20, 24)
    for n, h in enumerate(hs):
        for yy in range(y, min(H, y + h)):
            for x in range(W):
                k = math.floor((x + .5 - 160) / (58 * (yy - 92) / (H - 92)) + 0.5) if yy > 120 else 0
                c.set(x, yy, P['grassA'] if (n + k) % 2 else P['grassB'])
        y += h
    if dusk:
        for yy in range(108, 132):                      # the left stand's shadow, and the sun raking the rest
            edge = 132 - (yy - 108) * 6.5
            for x in range(W):
                if x < edge + 12 and (edge + 12 - x) / 26 > (BAYER[yy % 4][x % 4] + .5) / 16:
                    c.set(x, yy, P['shade'])
                elif x > edge + 14 and yy < 119:
                    t = min(1, (x - edge) / 200) * (1 - (yy - 108) / 11)
                    if t * 0.9 > (BAYER[yy % 4][x % 4] + .5) / 16:
                        c.set(x, yy, look['grass_sun'])
    if night:                                           # the pool of light falls off toward the corners
        for yy in range(108, H):
            for x in range(W):
                t = max(0, abs(x - 160) - 96) / 64
                if t * 0.8 > (BAYER[yy % 4][x % 4] + .5) / 16 and c.get(x, yy) in (P['grassA'], P['grassB']):
                    c.set(x, yy, P['shade'])
    # the board
    frame, edge, face = look['board']
    c.rect(125, 77, 70, 19, frame)
    c.rect(125 if look['light'][0] < 0 else 193, 77, 2, 19, edge); c.rect(125, 77, 70, 1, edge)
    c.rect(128, 80, 64, 16, face if night else INK)
    c.t3(134, 84, NOW.FEET, P['score']); c.t3(134, 91, NOW.PARK, P['chalk'])
    for i in range(3):
        c.rect(168 + i * 5, 84, 3, 3, P['score'] if i < 1 else frame)
    for dx in (6, 55):
        x = 128 + dx
        c.rect(x, 69, 1, 8, look['grey'][3])
        for j in range(3):
            c.rect(x + 1, 69 + j, 5 - j, 1, look['red'][2] if j < 2 else look['red'][0])
    for ex in (40, 280):
        c.line(160, 196, ex, 104, P['chalk'])
        c.line(160 + (1 if ex > 160 else -1), 196, (160 + ex) / 2, 150, P['chalk'])
    # the mound and the plate circle, shaped by the light
    sgn = -1 if look['light'][0] < 0 else 1
    c.ellipse(160, 120.5, 16, 5, d_dd); c.ellipse(160 + sgn, 119.3, 15, 4.2, d_d); c.ellipse(160 + 2 * sgn, 118.8, 13, 3.2, d_m)
    c.ellipse(160 + 7 * sgn, 118, 5, 1.4, d_l); c.rect(157, 117, 6, 1, P['chalk'])
    c.ellipse(160, 205, 94, 25.5, d_dd); c.ellipse(160 + sgn, 205.4, 93, 24.6, d_d); c.ellipse(160 + 3 * sgn, 206, 90, 23.5, d_m)
    V.speckle(c, 11, (70, 184, 252, 223), 90, [d_l, d_d], d_m)
    for s_ in (-1, 1):
        pts = [(160 + s_ * 22, 189), (160 + s_ * 68, 189), (160 + s_ * 82, 221), (160 + s_ * 26, 221)]
        for i in range(4):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % 4]
            c.line(x0, y0, x1, y1, P['chalk'])
    for j, (x0, x1) in enumerate([(152, 168), (152, 168), (153, 167), (155, 165), (157, 163), (159, 161)]):
        c.rect(x0, 190 + j, x1 - x0, 1, P['chalk']); c.px(x1 - 1, 190 + j, look['ball_lo'])
    table = {P['grassA']: P['shade'], P['grassB']: P['shade'], d_m: d_d, d_d: d_dd, d_l: d_d}
    ps, bs = pitcher(2, look), batter(1 if beat == 'contact' else 0, look)
    cast(c, ps, 160, 117, dict(look, shadows=[(k, r_, 14) for k, r_, _ in look['shadows']]), table)
    cast(c, bs, 106, 214, look, table, ground=batter_ground(1 if beat == 'contact' else 0))
    c.blit(ps, 160 - ps.ox, 117 - ps.oy)
    NOW.zone(c, P['chalk'])
    c.blit(bs, 106 - bs.ox, 214 - bs.oy)
    if beat == 'contact':
        contact_fx(c, look)
    else:
        bx, by, r = NOW.BALL
        c.baseball(bx, by, r, look['ball_hi'])
        c.px(bx + 2, by + 2, look['ball_lo']); c.px(bx + 1, by + 3, look['ball_lo']); c.px(bx + 3, by + 1, look['ball_lo'])
        c.t3(8, H - 12, '87 MPH', P['chalk'], shadow=INK)
    c.t3(8, 8, NOW.HUD, P['chalk'], shadow=INK)
    return c


# ======================================================================================
# The flight camera: the result hold at dusk, and the close framing after dark
# ======================================================================================

def fireworks(c, bursts, seed=2):
    g = random.Random(seed)
    for cx, cy, r, tones in bursts:
        for n in range(20):
            ang = n / 20 * 2 * math.pi + g.random() * 0.2
            for k, frac in enumerate((0.45, 0.72, 1.0)):
                rr = r * frac * (0.9 + g.random() * 0.2)
                x, y = cx + math.cos(ang) * rr, cy + math.sin(ang) * rr * 0.92 + frac * frac * 5
                tone = tones[(n + k) % len(tones)]
                if k == 2:
                    c.rect(x, y, 2, 2, tone)
                else:
                    c.px(x, y, tone)
        c.px(cx, cy, P['chalk'])


def flight(look, cam, mode='flight'):
    night, dusk = look['name'] == 'night', look['name'] == 'dusk'
    i = S.ball_index(cam)
    vanish = next(n for n, p in enumerate(S.PTS) if p[0] >= S.WALL and p[1] <= S.stands_h(p[0]))
    if mode == 'result':
        i = vanish
    fr = S.Frame(cam, S.PTS[i][1]); g0 = fr.ground
    c = Canvas(W, H)
    sky(c, look, bottom=g0, stretch=g0 / 96 * 0.97)
    if night:
        stars(c, 9, 120, 110)
    sun(c, look, at=(58, g0 - 27, 11, 34) if dusk else ((230, 40, 8, 20) if night else None), clip_y=g0)
    clouds(c, look, {'dusk': ((120, 30, 40, 3.2), (158, 37, 24, 2), (250, 58, 46, 3.6), (286, 66, 22, 2), (40, 70, 30, 2.6),
                              (204, 96, 34, 2.6)),
                     'night': ((110, 50, 40, 3), (60, 84, 30, 2.4)), 'day': ((90, 50, 26, 5), (230, 40, 22, 4))}[look['name']])
    if mode == 'result':
        fireworks(c, [(96, 58, 26, [P['score'], look['red'][2], P['chalk']]), (168, 34, 20, [P['chalk'], P['skin'], P['score']]),
                      (236, 70, 17, [look['red'][2], P['score'], P['chalk']])])
    V.hills(c, look['hill'][0], 30, 5, baseline=g0, r=(34, 60)); V.hills(c, look['hill'][1], 17, 9, baseline=g0, r=(20, 34))
    leafy(c, look, 0, int(fr.x(S.WALL)), int(g0), 21)
    if True:                                            # two towers behind the stands, in every phase; lit when `night`
        for feet, tall in ((40, 168), (128, 182)):
            x, top = fr.x(S.WALL + feet), fr.y(tall)
            for y in range(int(top + 8), int(fr.y(S.TOP))):
                t = (y - top) / max(1, (g0 - top)); half = 2 + t * 4
                c.set(int(x - half), y, col('#446688')); c.set(int(x + half), y, col('#446688'))
                if int(y - top) % 9 == 0:
                    c.rect(x - half, y, half * 2 + 1, 1, col('#446688'))
                elif int(y - top) % 9 == 4:
                    c.line(x - half, y - 4, x + half, y + 4, col('#446688'))
            bx, by = x - 10, top - 4
            for yy in range(int(by - 12), int(by + 22)):
                for xx in range(int(bx - 14), int(bx + 36)):
                    d = math.hypot((xx - (bx + 10)) / 24, (yy - (by + 5)) / 14)
                    if night and d < 1 and (1 - d) > (BAYER[yy % 4][xx % 4] + .5) / 16:
                        c.set(xx, yy, col('#444488') if d > 0.55 else col('#6666AA'))
            c.rect(bx - 1, by - 1, 22, 13, INK)
            for j in range(3):
                for k in range(5):
                    c.rect(bx + k * 4, by + j * 4, 3, 3, col('#EEEEAA') if night else col('#446688'))
                    if night:
                        c.px(bx + k * 4 + 1, by + j * 4 + 1, P['chalk'])
    deck_mass, roof, lamp, column = look['deck']
    S.upper_deck(c, fr, deck_mass, roof, column, column, glow=lamp)
    S.pennant_string(c, fr, column, [look['red'][2], roof])
    S.checker_mow(c, fr, P['grassA'], P['grassB'])
    if dusk:
        for yy in range(int(g0), int(g0) + 9):
            for x in range(W):
                t = max(0, 1 - x / (W * 0.8)) * (1 - (yy - g0) / 9)
                if t > (BAYER[yy % 4][x % 4] + .5) / 16:
                    c.set(x, yy, look['grass_sun'])
    d_l, d_m, d_d, d_dd = look['dirt']
    S.field_marks(c, fr, d_m, d_d, d_l, shadow=INK)
    ts = Canvas(7, 8); ts.stamp(S.TINY_A, {'B': look['wood'][2], 'R': look['red'][2], 'S': look['skin'][2], 'K': look['grey'][2]}, 0, 0)
    if dusk:
        for k in range(1, 22):
            if k < 12 or k % 2 == 0:
                c.px(fr.x(0) + k, g0 + 1 + k // 8, P['shade'])
    c.blit(ts, int(fr.x(0)) - 4, int(g0) - 8)
    S.trail(c, fr, i, [look['sun'][0] if look['sun'] else P['chalk'], P['chalk']], cam)
    X, Y = fr.x(S.PTS[i][0]), fr.y(S.PTS[i][1]) - 3
    if mode == 'flight':
        if cam == 'wide':
            c.rect(X + 1, g0 + 2, 5, 1, P['shade'])
            c.rect(X - 1, Y - 1, 4, 4, P['chalk']); c.px(X - 1, Y - 1, look['ball_hi']); c.px(X + 2, Y + 2, look['ball_lo']); c.px(X + 1, Y + 1, P['cap'])
        else:
            c.rect(X, g0 + 1, 8, 2, P['shade'])
            c.baseball(X, Y, 3, look['ball_hi']); c.px(X + 2, Y + 2, look['ball_lo']); c.px(X + 1, Y + 3, look['ball_lo'])
    wall_x, wall_top = fr.x(S.WALL), fr.y(S.WALL_H)
    wl, wm, wd = look['wall']
    c.rect(wall_x, wall_top, W - wall_x, g0 - wall_top, wm); c.rect(wall_x, wall_top + 1, W - wall_x, 1, wl)
    bayer_gradient(c, wall_x, wall_top + 2, W - wall_x, max(1, g0 - wall_top - 2), wm, wd)
    f = S.WALL + 20
    while fr.x(f) < W:
        c.rect(fr.x(f), wall_top + 1, 1, g0 - wall_top - 1, wd); f += 20
    c.rect(wall_x, wall_top, W - wall_x, 1, P['score']); c.rect(wall_x, wall_top - 1, 2, g0 - wall_top + 1, look['pole'][0])
    mass, lip, under = look['stand_lit']
    S.tiers(c, fr, under, lip, under=mass, edge=lip)
    S.crowd_rows(c, fr, 12, look['heads_lit'], look['shirts_lit'], aisle=mass)
    top_y = fr.y(S.TOP)
    span = 12 if cam == 'close' else 7
    for yy in range(int(top_y) + 2, int(top_y) + span):
        for x in range(int(fr.x(S.WALL + 40)), W):
            t = 1 - (yy - top_y) / span
            if yy > fr.y(S.stands_h((x - fr.ox) / fr.scale)) + 1 and c.get(x, yy) != lip and t * 0.8 > (BAYER[yy % 4][x % 4] + .5) / 16:
                c.set(x, yy, under)
    S.foul_pole(c, fr, look['pole'][0], look['pole'][1], look['pole'][1])
    S.board(c, fr, under, mass, INK, [look['grey'][3], roof], lamp, lip=roof, glow=roof)
    S.flags(c, fr, look['grey'][3], look['red'][2], look['red'][0])
    wall_h = S.WALL_H * fr.scale
    ly = g0 - wall_h + 3 if wall_h >= 11 else g0 - wall_h - 8
    c.rect(wall_x + 5, ly - 1, 13, 7, INK); c.t3(wall_x + 6, ly, '395', P['score'])
    c.t3(8, 8, '108 MPH', P['score'], 2, INK); c.t3(8, 20, '29 DEG', P['score'], 2, INK); c.t3(8, 34, 'FASTBALL', P['chalk'], 1, INK)
    if mode == 'flight':
        c.t3(min(W - 30, X + 6), max(6, Y - 10), '%d FT' % round(S.PTS[i][0]), P['chalk'], 1, INK)
    else:
        px_, py_ = round(fr.x(S.PTS[vanish][0])), round(fr.y(S.PTS[vanish][1]))   # the pop where it went in
        c.rect(px_ - 3, py_, 7, 1, P['chalk']); c.rect(px_, py_ - 3, 1, 7, P['chalk'])
        for ax, ay in ((-2, -2), (2, -2), (-2, 2), (2, 2)):
            c.px(px_ + ax, py_ + ay, P['chalk'])
        text = '%d FT' % round(S.DIST)
        t5(c, W / 2 - len(text) * 6 * 3 / 2 + 3, 52, text, P['score'], 3, INK)
        line = 'HR 2 OF 3'
        c.t3(round(W / 2 - (len(line) * 8 - 2) / 2), 76, line, P['score'], 2, INK)
        t5(c, W / 2 - 6 * 3, 90, 'HR', look['red'][2], 3, INK)
        line = 'STREAK 2'
        c.t3(round(W / 2 - len(line) * 4), 118, line, P['score'], 2, INK)
    c.t3(W - 10 - len(NOW.PARK) * 4, H - 12, NOW.PARK, P['chalk'], 1, INK)
    return c



# ======================================================================================
# Round three: the clock drives the sky. Six phases, one drawing, the lines reloaded.
# ======================================================================================

DUSK.update(dim_side=-1, crowd=0.88, towers=False, stars=0, mist=None, vignette=False, cumulus=False, flat=False,
            clouds_atbat=((150, 22, 30, 2.4), (214, 40, 36, 3.2), (96, 46, 22, 2), (270, 52, 20, 2)),
            clouds_flight=((120, 30, 40, 3.2), (158, 37, 24, 2), (250, 58, 46, 3.6), (286, 66, 22, 2), (40, 70, 30, 2.6),
                           (204, 96, 34, 2.6)),
            flight_sun=('ground', 58, 27, 11, 34), flight_wash=True, flight_sky=None)
NIGHT.update(dim_side=0, crowd=0.92, towers=True, stars=70, mist=None, vignette=True, cumulus=False, flat=True,
             clouds_atbat=((120, 40, 34, 3), (200, 58, 26, 2.2)), clouds_flight=((110, 50, 40, 3), (60, 84, 30, 2.4)),
             flight_sun=('sky', 230, 40, 8, 20), flight_wash=False, flight_sky=None)
DAY.update(dim_side=0, crowd=0.8, towers=False, stars=0, mist=None, vignette=False, cumulus=True, flat=False,
           light=(-0.15, -0.99), shadows=[(-0.1, 0.1, 99)],
           clouds_atbat=((60, 40, 22, 4), (214, 34, 26, 5), (150, 58, 16, 3)), clouds_flight=((90, 50, 26, 5), (230, 40, 22, 4)),
           flight_sun=None, flight_wash=False, flight_sky=None)

DUSK.update(L(bird='#EECC88', blimp=['#EECC88', '#CC8888'], tower=['#446688', '#444488', '#6666AA', '#EEEEAA']))
NIGHT.update(L(bird='#8888AA', blimp=['#8888AA', '#444466'], tower=['#446688', '#444488', '#6666AA', '#EEEEAA']))
DAY.update(L(bird='#222244', blimp=['#EEEEEE', '#AACCEE'], tower=['#446688', '#444488', '#6666AA', '#EEEEAA']))

DAWN = dict(DUSK)
DAWN.update(L(name='dawn',
              sky=[(0, '#222266'), (8, '#222266'), (24, '#444488'), (30, '#444488'), (46, '#8888CC'), (50, '#8888CC'),
                   (62, '#CCAACC'), (66, '#CCAACC'), (76, '#EEAAAA'), (79, '#EEAAAA'), (88, '#EECCAA'), (90, '#EECCAA'),
                   (96, '#EEEECC')],
              cloud=['#8888CC', '#CCAACC', '#EEAAAA', '#EECCAA'], sun=['#EEEECC', '#EECCAA'], sun_at=(293, 63, 9, 27),
              hill=['#8888AA', '#666688'], tree=['#224444', '#226644', '#88CC88'], light=(0.85, -0.5),
              stand_lit=['#666688', '#EECCCC', '#444466'], stand_dim=['#444466', '#8888AA', '#222244'],
              shirts_lit=['#CC2222', '#AAAACC', '#CCAACC', '#EEAAAA', '#8888AA', '#6666AA'],
              shirts_dim=['#660022', '#444488', '#666688', '#6666AA'],
              deck=['#666688', '#EECCCC', '#EEEECC', '#444466'],
              red=['#660022', '#AA2222', '#CC2222', '#EE8888'], grey=['#444466', '#666688', '#8888AA', '#CCCCEE'],
              skin=['#884444', '#CC8866', '#EEAA88', '#EECCCC'], board=['#444466', '#EECCCC', '#222244'],
              ball_hi='#EEEECC', mist='#CCCCEE', bird='#EECCAA', blimp=['#EECCCC', '#CCAACC'],
              shadows=[(0.9, 0.22, 62)]))
DAWN.update(dim_side=+1, crowd=0.25,
            clouds_atbat=((170, 24, 30, 2.4), (106, 42, 36, 3.2), (226, 50, 22, 2), (50, 56, 20, 2)),
            clouds_flight=((120, 34, 40, 3.2), (250, 60, 46, 3.4), (60, 78, 30, 2.4)),
            flight_sun=None, flight_wash=False,
            flight_sky=[(y, col(h)) for y, h in [(0, '#444488'), (10, '#444488'), (30, '#8888CC'), (38, '#8888CC'),
                                                  (56, '#CCAACC'), (62, '#CCAACC'), (74, '#EEAAAA'), (79, '#EEAAAA'),
                                                  (88, '#8888AA'), (91, '#8888AA'), (96, '#6666AA')]])

MORNING = dict(DAY)
MORNING.update(L(name='morning',
                 sky=[(0, '#4466CC'), (24, '#4466CC'), (46, '#66AAEE'), (54, '#66AAEE'), (72, '#AACCEE'), (78, '#AACCEE'),
                      (90, '#CCEEEE'), (96, '#EEEECC')],
                 sun=['#EEEECC', '#AACCEE'], sun_at=(286, 22, 7, 16), light=(0.7, -0.7),
                 stand_lit=['#666688', '#EEEECC', '#444466'], stand_dim=['#666688', '#EEEECC', '#444466'],
                 ball_hi='#EEEECC', shadows=[(0.5, 0.16, 99)]))
MORNING.update(crowd=0.5, clouds_atbat=((70, 44, 22, 4), (180, 30, 24, 5)), clouds_flight=((110, 46, 26, 5), (250, 60, 20, 4)))

TWILIGHT = dict(NIGHT)
TWILIGHT.update(L(name='twilight',
                  sky=[(0, '#000022'), (14, '#000022'), (34, '#222244'), (40, '#222244'), (58, '#222266'), (62, '#222266'),
                       (76, '#444488'), (80, '#444488'), (88, '#886688'), (90, '#886688'), (96, '#CC8866')],
                  cloud=['#444466', '#664466', '#886688', '#CC8866'], hill=['#444466', '#222244']))
TWILIGHT.update(sun=None, sun_at=None, stars=22, vignette=False, flight_sun=None,
                clouds_atbat=((140, 46, 34, 3), (226, 62, 26, 2.2), (70, 70, 22, 2)),
                clouds_flight=((120, 70, 40, 3), (240, 110, 34, 2.6), (60, 128, 30, 2.4)))


def clouds(c, look, spots):
    t = look['cloud']
    lx, ly = look['light']
    for x, y, rx, ry in spots:
        if look['cumulus']:
            own = {}
            for dx, r in ((-rx * .5, ry * 1.6), (-rx * .1, ry * 2.6), (rx * .3, ry * 2.0), (rx * .62, ry * 1.2)):
                for px_, py_, nx, ny in m_ellipse(x + dx, y - r * 0.6, r, r):
                    if py_ < y:
                        own[(px_, py_)] = (nx, ny)
            for (px_, py_), (nx, ny) in own.items():
                l = nx * (lx * 0.6) + ny * -0.8
                c.set(px_, py_, t[3] if py_ >= y - 1 else (t[2] if (l < -0.35 or py_ >= y - 3) else t[0]))
        else:
            for px_, py_, nx, ny in m_ellipse(x, y, rx, ry):
                tone = t[0] if ny < -0.35 else (t[3] if (ny > 0.45 and nx > -0.5) else (t[2] if ny > 0.05 else t[1]))
                if abs(nx) > 0.78 and ((px_ + py_) & 1):
                    continue
                c.set(px_, py_, tone)


def pitcher(frame, look):
    rows = PITCH[frame]
    if look['light'][0] > 0.3:                      # lit from the right: flip the modelling, not the pose
        swap = str.maketrans('WLu', 'uuW')
        rows = [r.replace('WL', '\x00').translate(swap).replace('\x00', 'uU') for r in rows]
    s = Sprite(44, 44, 16, 40)
    red, grey, skin, wood = look['red'], look['grey'], look['skin'], look['wood']
    leg = {'R': red[2], 'r': red[0], 'H': red[3], 'S': skin[2], 's': skin[1], 'U': grey[2], 'u': grey[0],
           'L': grey[2] if look['flat'] else grey[3], 'W': grey[3], 'K': INK, 'G': wood[1], 'g': wood[0],
           'B': P['chalk'], 'N': red[1]}
    s.lstamp(rows, leg, -5, -len(rows))
    return s


def wing(c, look, side, seed, tier='full'):
    lit = side != look['dim_side']
    mass, lip, under = look['stand_lit'] if lit else look['stand_dim']
    heads = look['heads_lit'] if lit else look['heads_dim']
    shirts = look['shirts_lit'] if lit else look['shirts_dim']
    deck_mass, roof, lamp, column = look['deck']
    full = tier == 'full'
    head = 10 if full else 2                                # rows under the roof that seat nobody
    xs = range(0, 124) if side < 0 else range(196, W)
    g = random.Random(seed)
    for x in xs:
        top = wing_top(x, tier)
        c.rect(x, top, 1, 96 - top, mass)
        c.set(x, top, roof if full else lip); c.set(x, top + 1, under)
        if full:
            c.rect(x, top + 2, 1, 5, deck_mass)
            if x % 6 == 2:
                c.set(x, top + 4, lamp); c.set(x + 1, top + 4, lamp)
            if x % 17 == 5:
                c.rect(x, top + 7, 1, 3, column)
        for k in (1, 2):
            yy = 96 - 9 * k
            if yy > top + head:
                c.set(x, yy, lip)
    row, y = 0, 94
    while y > 64:
        for x in xs:
            if (x + row) % 2 or y - 1 <= wing_top(x, tier) + head or (96 - y) % 9 == 0 or (96 - (y - 1)) % 9 == 0:
                continue
            if x % 23 == 11:
                c.set(x, y, under); c.set(x, y - 1, under); continue
            if g.random() < look['crowd']:
                c.set(x, y - 1, g.choice(heads)); c.set(x, y, g.choice(shirts))
        y -= 3; row += 1
    edge = 123 if side < 0 else 196
    c.rect(edge, wing_top(edge, tier), 1, 96 - wing_top(edge, tier), under)


def near_piece(c, look, kind, x, base):
    """§17's near piece in the stand colours, with one lit edge on the side of the light."""
    mass, lip, under = look['stand_lit']
    e = -1 if look['light'][0] < 0 else 1                   # which edge the light catches
    if kind == 'waterTower':
        c.rect(x - 6, base - 18, 13, 8, mass); c.rect(x - 5, base - 19, 11, 1, mass); c.rect(x - 2, base - 21, 5, 2, under)
        c.rect(x - 6 if e < 0 else x + 6, base - 18, 1, 8, lip); c.rect(x - 6, base - 13, 13, 1, under)
        for lx in (-5, 5):
            c.rect(x + lx, base - 10, 1, 10, under)
        c.line(x - 5, base - 9, x + 5, base - 1, under); c.line(x + 5, base - 9, x - 5, base - 1, under)
    elif kind == 'lightPoles':
        for dx in (-13, 12):
            c.rect(x + dx, base - 20, 2, 20, under); c.rect(x + dx - 4, base - 24, 10, 4, mass)
            c.rect(x + dx - 4 if e < 0 else x + dx + 5, base - 24, 1, 4, lip)
            if look['towers']:
                for i in range(3):
                    c.rect(x + dx - 3 + i * 3, base - 23, 2, 2, look['deck'][2])
    elif kind == 'house':
        c.rect(x - 7, base - 9, 14, 9, mass)
        for j in range(7):
            c.rect(x - j - 1, base - 15 + j, j * 2 + 2, 1, under)
            c.set(x - j - 1 if e < 0 else x + j, base - 15 + j, lip)
        c.rect(x - 2, base - 5, 3, 5, under); c.rect(x + 3, base - 7, 2, 2, look['deck'][2] if look['towers'] else under)


def at_bat(look, beat='pitch', tier='full', park=None, feet=None, pole=28, near=None):
    c = Canvas(W, H)
    sky(c, look)
    if look['stars']:
        stars(c, 5, 70, look['stars'])
    sun(c, look)
    clouds(c, look, look['clouds_atbat'])
    V.hills(c, look['hill'][0], 20, 5, r=(30, 52)); V.hills(c, look['hill'][1], 12, 9, r=(18, 30))
    if tier == 'full':
        leafy(c, look, 118, 202, 96, 21)
    else:                                                   # a low stand, or none: the far side of town shows over it
        leafy(c, look, 0, W, 96, 21)
    towers(c, look)                                         # by day too (Dwight, 2026-09-21): dark until the lamps come on
    if tier != 'fenceAndTrees':
        wing(c, look, -1, 3, tier); wing(c, look, +1, 4, tier)
    if near:
        kind, nx = near
        near_piece(c, look, kind, nx, 96 if tier == 'fenceAndTrees' else wing_top(nx, tier))
    lit, dark = look['pole'] if look['light'][0] < 0 else look['pole'][::-1]
    for x in (40, 280):
        c.rect(x, 96 - pole, 1, pole, lit); c.rect(x + 1, 96 - pole, 1, pole, dark); c.rect(x - 1, 96 - pole - 2, 4, 2, P['score'])
    wl, wm, wd = look['wall']
    c.rect(0, 96, W, 8, wm); c.rect(0, 97, W, 1, wl)
    bayer_gradient(c, 0, 98, W, 6, wm, wd)
    for x in range(10, W, 20):
        c.rect(x, 97, 1, 7, wd)
    c.rect(0, 96, W, 1, P['score'])
    d_l, d_m, d_d, d_dd = look['dirt']
    c.rect(0, 104, W, 4, d_m); bayer_gradient(c, 0, 104, W, 3, d_dd, d_m)
    y, hs = 108, (3, 3, 4, 4, 5, 6, 7, 8, 10, 12, 14, 17, 20, 24)
    for n, h in enumerate(hs):
        for yy in range(y, min(H, y + h)):
            for x in range(W):
                k = math.floor((x + .5 - 160) / (58 * (yy - 92) / (H - 92)) + 0.5) if yy > 120 else 0
                c.set(x, yy, P['grassA'] if (n + k) % 2 else P['grassB'])
        y += h
    if look['dim_side']:                                 # the low sun: one stand's shadow, the rest raked with light
        for yy in range(108, 132):
            edge = 132 - (yy - 108) * 6.5
            for x in range(W):
                xm = x if look['dim_side'] < 0 else W - 1 - x
                if xm < edge + 12 and (edge + 12 - xm) / 26 > (BAYER[yy % 4][x % 4] + .5) / 16:
                    c.set(x, yy, P['shade'])
                elif xm > edge + 14 and yy < 119:
                    t = min(1, (xm - edge) / 200) * (1 - (yy - 108) / 11)
                    if t * 0.9 > (BAYER[yy % 4][x % 4] + .5) / 16:
                        c.set(x, yy, look['grass_sun'])
    if look['vignette']:
        for yy in range(108, H):
            for x in range(W):
                t = max(0, abs(x - 160) - 96) / 64
                if t * 0.8 > (BAYER[yy % 4][x % 4] + .5) / 16 and c.get(x, yy) in (P['grassA'], P['grassB']):
                    c.set(x, yy, P['shade'])
    frame, edge, face = look['board']
    c.rect(125, 77, 70, 19, frame)
    c.rect(125 if look['light'][0] < 0 else 193, 77, 2, 19, edge); c.rect(125, 77, 70, 1, edge)
    c.rect(128, 80, 64, 16, face)
    c.t3(134, 84, feet or NOW.FEET, P['score']); c.t3(134, 91, park or NOW.PARK, P['chalk'])
    for i in range(3):
        c.rect(168 + i * 5, 84, 3, 3, P['score'] if i < 1 else frame)
    for dx in (6, 55):
        x = 128 + dx
        c.rect(x, 69, 1, 8, look['grey'][3])
        for j in range(3):
            c.rect(x + 1, 69 + j, 5 - j, 1, look['red'][2] if j < 2 else look['red'][0])
    for ex in (40, 280):
        c.line(160, 196, ex, 104, P['chalk'])
        c.line(160 + (1 if ex > 160 else -1), 196, (160 + ex) / 2, 150, P['chalk'])
    sgn = -1 if look['light'][0] < 0 else 1
    c.ellipse(160, 120.5, 16, 5, d_dd); c.ellipse(160 + sgn, 119.3, 15, 4.2, d_d); c.ellipse(160 + 2 * sgn, 118.8, 13, 3.2, d_m)
    c.ellipse(160 + 7 * sgn, 118, 5, 1.4, d_l); c.rect(157, 117, 6, 1, P['chalk'])
    c.ellipse(160, 205, 94, 25.5, d_dd); c.ellipse(160 + sgn, 205.4, 93, 24.6, d_d); c.ellipse(160 + 3 * sgn, 206, 90, 23.5, d_m)
    V.speckle(c, 11, (70, 184, 252, 223), 90, [d_l, d_d], d_m)
    for s_ in (-1, 1):
        pts = [(160 + s_ * 22, 189), (160 + s_ * 68, 189), (160 + s_ * 82, 221), (160 + s_ * 26, 221)]
        for i in range(4):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % 4]
            c.line(x0, y0, x1, y1, P['chalk'])
    for j, (x0, x1) in enumerate([(152, 168), (152, 168), (153, 167), (155, 165), (157, 163), (159, 161)]):
        c.rect(x0, 190 + j, x1 - x0, 1, P['chalk']); c.px(x1 - 1, 190 + j, look['ball_lo'])
    if look['mist']:                                     # ground mist, out by the wall and nowhere near the zone
        for yy in range(99, 121):
            d = 1 - abs(yy - 107) / (9 if yy < 107 else 14)
            for x in range(W):
                if d * 0.62 > (BAYER[yy % 4][(x + yy // 3) % 4] + .5) / 16 and not (124 <= x < 196 and yy < 96):
                    c.set(x, yy, look['mist'])
    table = {P['grassA']: P['shade'], P['grassB']: P['shade'], d_m: d_d, d_d: d_dd, d_l: d_d}
    ps, bs = pitcher(2, look), batter(1 if beat == 'contact' else 0, look)
    cast(c, ps, 160, 117, dict(look, shadows=[(k, r_, 14) for k, r_, _ in look['shadows']]), table)
    cast(c, bs, 106, 214, look, table, ground=batter_ground(1 if beat == 'contact' else 0))
    c.blit(ps, 160 - ps.ox, 117 - ps.oy)
    NOW.zone(c, P['chalk'])
    c.blit(bs, 106 - bs.ox, 214 - bs.oy)
    if beat == 'contact':
        contact_fx(c, look)
    else:
        bx, by, r = NOW.BALL
        c.baseball(bx, by, r, look['ball_hi'])
        c.px(bx + 2, by + 2, look['ball_lo']); c.px(bx + 1, by + 3, look['ball_lo']); c.px(bx + 3, by + 1, look['ball_lo'])
        c.t3(8, H - 12, '87 MPH', P['chalk'], shadow=INK)
    c.t3(8, 8, NOW.HUD if park is None else '%s  12 PITCHES' % park, P['chalk'], shadow=INK)
    return c


_flight_v2 = flight


def flight(look, cam, mode='flight'):
    """The same flight camera, reading its sky, sun, towers and crowd off the phase."""
    shim = dict(look)
    shim['name'] = 'night' if look['towers'] else ('dusk' if look.get('flight_wash') else 'day')
    if look.get('flight_sky'):
        shim['sky'] = look['flight_sky']
    fs = look.get('flight_sun')
    real_sun, real_clouds, real_stars, real_crowd = globals()['sun'], globals()['clouds'], globals()['stars'], S.crowd_rows

    def sun_(c, lk, at=None, clip_y=None):
        if fs is None or not look['sun']:
            return
        g0 = clip_y if clip_y is not None else 176
        pos = (fs[1], g0 - fs[2], fs[3], fs[4]) if fs[0] == 'ground' else (fs[1], fs[2], fs[3], fs[4])
        real_sun(c, dict(look, name=look['name']), at=pos, clip_y=clip_y)

    def clouds_(c, lk, spots):
        real_clouds(c, look, look['clouds_flight'])

    def stars_(c, seed, y_max, n=70):
        if look['stars']:
            real_stars(c, seed, y_max, int(look['stars'] * 1.6))

    def crowd_(c, fr, seed, heads, shirts, aisle=None, presence=0.86):
        real_crowd(c, fr, seed, heads, shirts, aisle=aisle, presence=look['crowd'])

    globals()['sun'], globals()['clouds'], globals()['stars'], S.crowd_rows = sun_, clouds_, stars_, crowd_
    try:
        return _flight_v2(shim, cam, mode)
    finally:
        globals()['sun'], globals()['clouds'], globals()['stars'], S.crowd_rows = real_sun, real_clouds, real_stars, real_crowd


# 21 September at latitude 40 on the zone meridian, daylight saving on: DESIGN.md §20's own table
PHASES = [('DAWN', '06:08-07:38', DAWN), ('MORNING', '07:38-10:52', MORNING), ('MIDDAY', '10:52-17:26', DAY),
          ('GOLDEN HOUR', '17:26-18:56', DUSK), ('TWILIGHT', '18:56-19:36', TWILIGHT), ('NIGHT', '19:36-06:08', NIGHT)]


def cycle(name, render):
    """Six frames, three across, each under a strip naming its phase and its clock on 21 September."""
    strip = 12
    sheet = Canvas(W * 3, (H + strip) * 2, INK)
    counts = {}
    for n, (phase, clock, look) in enumerate(PHASES):
        cv = render(look)
        counts[phase] = len(cv.used())
        x, y = (n % 3) * W, (n // 3) * (H + strip)
        sheet.blit(cv, x, y + strip)
        sheet.t3(x + 6, y + 4, '%d  %s' % (n + 1, phase), P['score'])
        sheet.t3(x + W - 6 - len(clock) * 4, y + 4, clock, P['chalk'])
        if n % 3:
            sheet.rect(x, y, 1, H + strip, INK)
    sheet.png(os.path.join(OUT, name + '.png'), 4)
    print(name, counts)


LADDER = [('SINGLE-A', 'fenceAndTrees', '330 FT', 16, ('house', 72)), ('DOUBLE-A', 'lowBleacher', '350 FT', 20, ('waterTower', 248)),
          ('TRIPLE-A', 'bleachers', '375 FT', 24, ('lightPoles', 72)), ('PARK 12', 'full', None, 28, None)]
TIER_WORDS = {'fenceAndTrees': 'NO STAND', 'lowBleacher': 'ONE TIER', 'bleachers': 'TWO TIERS', 'full': 'THE MOCK'}


def tiers(name, look):
    strip = 12
    sheet = Canvas(W * 2, (H + strip) * 2, INK)
    for n, (park, tier, feet, pole, near) in enumerate(LADDER):
        cv = at_bat(look, tier=tier, park=None if tier == 'full' else park, feet=feet, pole=pole, near=near)
        x, y = (n % 2) * W, (n // 2) * (H + strip)
        sheet.blit(cv, x, y + strip)
        sheet.t3(x + 6, y + 4, '%s  %s' % (park, TIER_WORDS[tier]), P['score'])
        if n % 2:
            sheet.rect(x, y, 1, H + strip, INK)
    sheet.png(os.path.join(OUT, name + '.png'), 4)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    tiers('c4-tiers-golden', DUSK)
    tiers('c4-tiers-night', NIGHT)
    cycle('c3-cycle-atbat', lambda look: at_bat(look))
    cycle('c3-cycle-flight', lambda look: flight(look, 'wide'))
