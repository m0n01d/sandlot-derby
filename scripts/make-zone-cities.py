#!/usr/bin/env python3
"""Generate `Core/Sources/DerbyCore/ZoneCities.swift` from the tz database.

The game never asks for the player's location (DESIGN.md §20, "The sun clock"):
it asks the device what time zone it is in and looks the zone's own city up
here. `/usr/share/zoneinfo/zone.tab` is the tz database's own table of exactly
that — one row per zone, with the city's coordinates in ISO 6709 — and it is
public domain, so the numbers can simply be baked into Core.

    python3 scripts/make-zone-cities.py            # rewrites ZoneCities.swift
    python3 scripts/make-zone-cities.py --check     # prints a diff and exits 1

Re-run it when the tz database moves a city or adds a zone. The aliases below
are not in `zone.tab` at all: they are the legacy identifiers iOS still reports
on some devices, which is a fact about iOS and not about the database, so they
are kept here by hand next to the table they extend.
"""

import argparse
import os
import sys

ZONE_TAB = "/usr/share/zoneinfo/zone.tab"
OUT = "Core/Sources/DerbyCore/ZoneCities.swift"

# Identifiers iOS can report that `zone.tab` does not carry, each mapped to the
# modern identifier that does. `TimeZone.current.identifier` is usually the
# modern one, but a device restored from an old backup — or one whose region
# was set years ago — can still hand over the left-hand name, and a zone the
# table misses falls all the way back to the assumed latitude (§20).
ALIASES = {
    "Asia/Calcutta": "Asia/Kolkata",
    "Asia/Saigon": "Asia/Ho_Chi_Minh",
    "Asia/Katmandu": "Asia/Kathmandu",
    "Asia/Rangoon": "Asia/Yangon",
    "America/Buenos_Aires": "America/Argentina/Buenos_Aires",
    "US/Eastern": "America/New_York",
    "US/Central": "America/Chicago",
    "US/Mountain": "America/Denver",
    "US/Pacific": "America/Los_Angeles",
    "US/Alaska": "America/Anchorage",
    "US/Hawaii": "Pacific/Honolulu",
    "Europe/Kiev": "Europe/Kyiv",
    "Asia/Chongqing": "Asia/Shanghai",
    "Australia/Canberra": "Australia/Sydney",
}


def iso6709(field):
    """Split `±DDMM±DDDMM` or `±DDMMSS±DDDMMSS` into degrees, north/east positive."""
    # The longitude's sign is the second one in the string, and it is the only
    # other +/- there is — so the split point is found rather than assumed from
    # a length, which differs between the two forms.
    cut = max(field.rfind("+"), field.rfind("-"))
    lat_s, lon_s = field[:cut], field[cut:]

    def degrees(s, deg_digits):
        sign = -1 if s[0] == "-" else 1
        body = s[1:]
        d = int(body[:deg_digits])
        m = int(body[deg_digits:deg_digits + 2])
        sec = int(body[deg_digits + 2:deg_digits + 4]) if len(body) > deg_digits + 2 else 0
        return sign * (d + m / 60 + sec / 3600)

    return degrees(lat_s, 2), degrees(lon_s, 3)


def read_table(path):
    cities = {}
    with open(path, encoding="ascii") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            lat, lon = iso6709(parts[1])
            cities[parts[2]] = (lat, lon)
    for old, new in ALIASES.items():
        if new in cities:
            cities[old] = cities[new]
        else:
            print(f"warning: alias {old} -> {new}, which zone.tab does not have", file=sys.stderr)
    return cities


HEADER = '''import Foundation

/// Where the city of a time zone is, to a tenth of a degree.
///
/// **Generated — do not edit by hand.** `scripts/make-zone-cities.py` builds this file from
/// `/usr/share/zoneinfo/zone.tab`, the tz database's own table, which is public domain. Re-run it
/// when the database moves a city or adds a zone.
///
/// The game never asks for the player's location and shows no menu to set one (DESIGN.md §1, §20).
/// It asks the device for its time zone, and a time-zone identifier already names a city —
/// `America/Boise` is Boise. That city is close enough for a sunrise: a player in the same zone as
/// the city sees the sun within a few minutes of the table, and one far from it sees an error that
/// grows with the distance (western China is the worst case in the world, at about two hours).
/// `SunClock` does the rest.
public enum ZoneCities {
    /// The latitude and longitude of each zone's city, north and east positive.
    public static let table: [String: (latitude: Double, longitude: Double)] = [
'''

FOOTER = '''    ]

    /// The city of `identifier`, or nil for a zone the table does not carry — in which case
    /// `SunClock`'s caller falls back to `SkyClockRules.assumedLatitudeDegrees` and the zone's own
    /// meridian (DESIGN.md §20).
    public static func coordinates(for identifier: String) -> (latitude: Double, longitude: Double)? {
        table[identifier]
    }
}
'''


def render(cities):
    rows = "".join(
        f'        "{name}": ({lat:.4f}, {lon:.4f}),\n'
        for name, (lat, lon) in sorted(cities.items())
    )
    return HEADER + rows + FOOTER


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="fail if the file is out of date")
    ap.add_argument("--zone-tab", default=ZONE_TAB)
    args = ap.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, OUT)
    swift = render(read_table(args.zone_tab))

    if args.check:
        with open(out, encoding="utf-8") as f:
            if f.read() == swift:
                print(f"{OUT} is up to date")
                return 0
        print(f"{OUT} is out of date; re-run without --check", file=sys.stderr)
        return 1

    with open(out, "w", encoding="utf-8") as f:
        f.write(swift)
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
