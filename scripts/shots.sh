#!/bin/zsh
# Build the app in a checkout and capture a burst of simulator screenshots.
# usage: shots.sh <checkout-root> <sim-name> <out-dir> [extra launch args...]
# Always launches with -nosave -mute. Add -autoslice to see the wide camera, -showstats for the board.
# <checkout-root> is the repo (or worktree) to build from — pass it literally, don't cd first.
#
# Environment variables (all optional):
#   FRAMES       how many screenshots to capture (default 16)
#   GAP          seconds to sleep between screenshots (default 0.35)
#   KEEP_BOOTED  1 = leave the simulator booted after the run instead of shutting it down (default 0)
#
# For a rare event's ~0.5 s two-frame burst, these stills lag the game clock too much to land
# inside the window (wave 3, CLAUDE.md Verification) — record video instead and pull frames:
#   xcrun simctl io <udid> recordVideo --codec h264 out.mp4   # stop it with Ctrl-C (SIGINT)
#   ffmpeg -i out.mp4 -vf fps=30 v%03d.png
set -uo pipefail
WT="$1"; SIM="$2"; OUT="$3"; shift 3
DD="/private/tmp/derby-dd/$SIM"
mkdir -p "$OUT" "$DD"
UDID=$(xcrun simctl list devices | grep -F "$SIM (" | head -1 | grep -oE '[0-9A-F]{8}-[0-9A-F-]{27}')
if [ -z "${UDID:-}" ]; then UDID=$(xcrun simctl create "$SIM" "iPhone 17") || exit 1; fi
echo "sim $SIM = $UDID"
cd "$WT/App" || exit 1
xcodegen generate >/dev/null || { echo "XCODEGEN FAILED"; exit 1; }
xcodebuild -project SandlotDerby.xcodeproj -scheme SandlotDerby -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=NO build > "$DD/build.log" 2>&1
if ! grep -q 'BUILD SUCCEEDED' "$DD/build.log"; then echo "BUILD FAILED"; grep -E 'error:|warning: unre' "$DD/build.log" | head -30; exit 1; fi
echo "BUILD SUCCEEDED"
APP="$DD/Build/Products/Debug-iphonesimulator/SandlotDerby.app"
xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl terminate "$UDID" com.m0n01d.sandlotderby 2>/dev/null
xcrun simctl install "$UDID" "$APP" || exit 1
xcrun simctl launch "$UDID" com.m0n01d.sandlotderby -nosave -mute "$@" >/dev/null || exit 1
sleep 1.5
for i in $(seq -w 1 ${FRAMES:-16}); do
  xcrun simctl io "$UDID" screenshot "$OUT/f$i.png" >/dev/null 2>&1
  sleep ${GAP:-0.35}
done
xcrun simctl terminate "$UDID" com.m0n01d.sandlotderby 2>/dev/null
[ "${KEEP_BOOTED:-0}" = 1 ] || xcrun simctl shutdown "$UDID"
# The app is landscape-only; rotate if the framebuffer came out portrait.
for f in "$OUT"/f*.png; do
  w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}'); h=$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')
  [ "$h" -gt "$w" ] && sips -r 270 "$f" >/dev/null
done
ls "$OUT" | wc -l | xargs echo "frames:"; echo "out: $OUT"
