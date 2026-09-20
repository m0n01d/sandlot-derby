#!/usr/bin/env bash
# Choose which of docs/icons' candidates ships as the app icon.
#
#     scripts/pick-icon.sh 01        # or 02, 03, 04, 05
#
# Copies that candidate's 1024 into App/Assets.xcassets/AppIcon.appiconset.
# The candidates themselves are regenerated with `python3 scripts/icons.py`.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
n="${1:-}"

if [ -z "$n" ]; then
  echo "usage: scripts/pick-icon.sh <01|02|03|04|05>" >&2
  ls "$root/docs/icons" | sed -n 's/-1024\.png$//p' | sed 's/^/  /' >&2
  exit 2
fi

src="$(ls "$root/docs/icons/${n}"-*-1024.png 2>/dev/null | head -1)"
if [ ! -f "$src" ]; then
  echo "no candidate $n in docs/icons" >&2
  exit 1
fi

cp "$src" "$root/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
echo "app icon is now $(basename "$src")"
