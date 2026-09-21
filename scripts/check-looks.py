#!/usr/bin/env python3
"""App/Sources/Look.swift against prototypes/04-golden-hour/golden.py, role by role.

golden.py is the oracle for §20's palette lines — docs/palette.md's phase tables were written out
of it — so a hand-typed Swift copy of forty-odd colours per phase needs a machine to say it still
agrees. This imports the prototype, parses the six `Look(...)` literals out of the Swift, and
compares the hex of every role it knows about. It also re-checks that every channel is one of the
Mega Drive's eight levels, which is the other half of the rule.

    python3 -B scripts/check-looks.py        # silent and exit 0, or a list of differences and 1
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'prototypes', '04-golden-hour'))
LOOK_SWIFT = os.path.join(ROOT, 'App', 'Sources', 'Look.swift')

GRID = (0x00, 0x22, 0x44, 0x66, 0x88, 0xAA, 0xCC, 0xEE)
# docs/palette.md's three legacy entries, which are off the grid and stay that way until Dwight
# decides. They are the sixteen's, not a phase line's, but `score` turns up in a crowd shirt.
LEGACY = {'#EEDD22', '#116633', '#221144'}

# Swift property -> golden.py key. A role in neither list is not compared; a role here that is
# missing from either side is an error, which is how a renamed field gets caught.
ROLES = [
    ('skyAtBat', 'sky'),
    ('skyFlight', 'flight_sky'),
    ('sun', 'sun'),
    ('cloud', 'cloud'),
    ('bird', 'bird'),
    ('blimp', 'blimp'),
    ('hill', 'hill'),
    ('tree', 'tree'),
    ('standLit', 'stand_lit'),
    ('standDim', 'stand_dim'),
    ('headsLit', 'heads_lit'),
    ('headsDim', 'heads_dim'),
    ('shirtsLit', 'shirts_lit'),
    ('shirtsDim', 'shirts_dim'),
    ('deck', 'deck'),
    ('tower', 'tower'),
    ('wall', 'wall'),
    ('grassSun', 'grass_sun'),
    ('dirt', 'dirt'),
    ('mist', 'mist'),
    ('red', 'red'),
    ('grey', 'grey'),
    ('skin', 'skin'),
    ('wood', 'wood'),
    ('glove', 'glove'),
    ('hair', 'hair'),
    ('pole', 'pole'),
    ('board', 'board'),
    ('ballHi', 'ball_hi'),
    ('ballLo', 'ball_lo'),
]


def hexes(value):
    """golden.py stores a colour as an (r, g, b) triple, a list of them, or a list of (y, triple)
    sky stops. Flatten whichever it is to a list of '#RRGGBB'."""
    if value is None:
        return []
    if isinstance(value, tuple) and len(value) == 3 and all(isinstance(v, int) for v in value):
        return ['#%02X%02X%02X' % value]
    if isinstance(value, (list, tuple)):
        out = []
        for item in value:
            if isinstance(item, tuple) and len(item) == 2:      # a sky stop: (y, colour)
                out += hexes(item[1])
            else:
                out += hexes(item)
        return out
    return []


def swift_blocks(text):
    """Every `static let <name> = Look(` … `)` in the file, as {name: body}. Bodies are found by
    balancing brackets rather than by a regex, so a role may wrap over as many lines as it likes."""
    out = {}
    for match in re.finditer(r'static let (\w+) = Look\(', text):
        depth, i = 1, match.end()
        while i < len(text) and depth:
            if text[i] in '([':
                depth += 1
            elif text[i] in ')]':
                depth -= 1
            i += 1
        out[match.group(1)] = text[match.end():i - 1]
    return out


def swift_roles(body):
    """The colours of each role in one `Look(...)` body, in order. A role starts at a line whose
    first token is `name:` while no bracket is open, and runs until they balance again — so a
    role may wrap over as many lines as it likes, and a nested `Shadow(...)` does not end it."""
    out, name, buf, depth = {}, None, '', 0
    for line in body.splitlines():
        line = re.sub(r'//.*$', '', line)            # a comment's brackets are not the code's
        rest = line
        if depth == 0:
            start = re.match(r'\s*(\w+):\s*(.*)$', line)
            if start:
                if name is not None:
                    out[name] = re.findall(r'0x([0-9A-Fa-f]{6})\b', buf)
                name, buf = start.group(1), ''
                rest = start.group(2)
        buf += rest + '\n'
        depth = max(0, depth + rest.count('(') + rest.count('[')
                    - rest.count(')') - rest.count(']'))
    if name is not None:
        out[name] = re.findall(r'0x([0-9A-Fa-f]{6})\b', buf)
    return out


def main():
    import golden

    phases = [
        ('dawn', golden.DAWN), ('morning', golden.MORNING), ('midday', golden.DAY),
        ('goldenHour', golden.DUSK), ('twilight', golden.TWILIGHT), ('night', golden.NIGHT),
    ]
    blocks = swift_blocks(open(LOOK_SWIFT).read())
    wrong = []

    for swift_name, look in phases:
        if swift_name not in blocks:
            wrong.append('Look.swift has no `static let %s`' % swift_name)
            continue
        roles = swift_roles(blocks[swift_name])
        for prop, key in ROLES:
            if prop not in roles:
                wrong.append('%s: Look.swift has no `%s:`' % (swift_name, prop))
                continue
            want = hexes(look.get(key))
            got = ['#' + h.upper() for h in roles[prop]]
            if got != want:
                wrong.append('%s.%s (golden %r)\n    swift  %s\n    golden %s'
                             % (swift_name, prop, key, ' '.join(got) or '(none)',
                                ' '.join(want) or '(none)'))
            for h in got:
                if h in LEGACY:
                    continue
                rgb = (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16))
                if any(v not in GRID for v in rgb):
                    wrong.append('%s.%s: %s is off the Genesis grid' % (swift_name, prop, h))

    if wrong:
        print('check-looks: %d difference(s) between Look.swift and golden.py\n' % len(wrong))
        for line in wrong:
            print('  ' + line)
        return 1
    print('check-looks: %d phases x %d roles agree with golden.py' % (len(phases), len(ROLES)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
