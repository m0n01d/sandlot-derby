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
#   DEVICE_TYPE  the device type <sim-name> is created as, if a simulator by that name doesn't
#                already exist (default "iPhone 17"), e.g. DEVICE_TYPE="iPad mini (A17 Pro)". Only
#                matters the first time a given <sim-name> is created — a simulator that already
#                exists keeps whatever device type it was made with, whatever <sim-name> matches it.
#   ROTATE       0 or 270 — overrides the auto-detected post-capture rotation for every frame
#                (see below) instead of deciding it from the simulator's own device type.
#
# The app is landscape-only. An iPhone's `simctl io screenshot` framebuffer comes out portrait
# with the landscape UI rotated into it, so frames get rotated 270 to come out upright. An iPad
# mini's framebuffer is also portrait, but the landscape app is drawn upright and letterboxed
# inside it already — rotating it would turn the picture sideways, so an iPad's frames instead get
# their top/bottom letterbox bars cropped off, computed from the image itself (never a guessed
# fixed crop) via ffmpeg's cropdetect.
#
# For a rare event's ~0.5 s two-frame burst, these stills lag the game clock too much to land
# inside the window (wave 3, CLAUDE.md Verification) — record video instead and pull frames:
#   xcrun simctl io <udid> recordVideo --codec h264 out.mp4   # stop it with Ctrl-C (SIGINT)
#   ffmpeg -i out.mp4 -vf fps=30 v%03d.png
set -uo pipefail

# $1's registered device type identifier (e.g. one containing "iPad" for any iPad mini), looked up
# in `xcrun simctl list -j devices` rather than assumed from the simulator's own name. Tries jq
# first, then python3 (both ubiquitous on a Mac that can run this script), then a best-effort
# plutil/grep parse as a last resort — do not assume jq is installed.
device_type_id() {
  local json; json=$(xcrun simctl list -j devices)
  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq -r --arg u "$1" '.devices[][] | select(.udid==$u) | .deviceTypeIdentifier' | head -1
  elif command -v python3 >/dev/null 2>&1; then
    echo "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
u = sys.argv[1]
for devs in d["devices"].values():
    for dev in devs:
        if dev.get("udid") == u:
            print(dev.get("deviceTypeIdentifier", ""))
            sys.exit(0)
' "$1"
  else
    # plutil pretty-prints the JSON with alphabetically ordered keys, so deviceTypeIdentifier
    # always lands a few lines above udid within the same device's block.
    echo "$json" | plutil -p - 2>/dev/null \
      | grep -B6 "\"udid\" => \"$1\"" | grep deviceTypeIdentifier \
      | sed -E 's/.*=> "(.*)"/\1/'
  fi
}

WT="$1"; SIM="$2"; OUT="$3"; shift 3
DD="/private/tmp/derby-dd/$SIM"
mkdir -p "$OUT" "$DD"
UDID=$(xcrun simctl list devices | grep -F "$SIM (" | head -1 | grep -oE '[0-9A-F]{8}-[0-9A-F-]{27}')
if [ -z "${UDID:-}" ]; then UDID=$(xcrun simctl create "$SIM" "${DEVICE_TYPE:-iPhone 17}") || exit 1; fi
echo "sim $SIM = $UDID"
DEVTYPE=$(device_type_id "$UDID")
IS_IPAD=0
case "$DEVTYPE" in *iPad*) IS_IPAD=1 ;; esac
echo "device type $DEVTYPE (iPad: $IS_IPAD)"
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
# The app is landscape-only; rotate an iPhone's portrait framebuffer, or crop an iPad's letterbox
# bars — see the header comment. ROTATE=0|270 overrides the auto-detected choice unconditionally.
for f in "$OUT"/f*.png; do
  w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}'); h=$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')
  if [ -n "${ROTATE:-}" ]; then
    [ "$ROTATE" = 270 ] && sips -r 270 "$f" >/dev/null
  elif [ "$IS_IPAD" = 1 ]; then
    if [ "$h" -gt "$w" ]; then
      # Crop the top/bottom letterbox bars off, computed from the image's own pure-black rows via
      # ffmpeg's cropdetect — never a guessed fixed crop. Leaves the frame alone (bars and all) if
      # cropdetect can't find a clean edge, rather than risk cutting into the game's own picture.
      CROP=$(ffmpeg -i "$f" -vf "cropdetect=24:2:0:skip=0" -f null - 2>&1 | grep -o 'crop=[0-9:]*' | tail -1)
      if [ -n "$CROP" ]; then
        CH=$(echo "$CROP" | cut -d: -f2); CY=$(echo "$CROP" | cut -d: -f4)
        ffmpeg -y -loglevel error -i "$f" -vf "crop=$w:$CH:0:$CY" "$f.crop.png" \
          && mv "$f.crop.png" "$f"
      fi
    fi
  else
    [ "$h" -gt "$w" ] && sips -r 270 "$f" >/dev/null
  fi
done
ls "$OUT" | wc -l | xargs echo "frames:"; echo "out: $OUT"
