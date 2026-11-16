#!/bin/zsh
# Simulator screenshot with a small copy to read (full-size images bloat the conversation).
# usage: Tools/sim-shot.sh <name> [size] [dir]
#   full size: <dir>/full/<name>.png   small copy (read this one): <dir>/<name>.jpg
# The small copy is a JPEG, 400 px on its longest side unless a size is given: a 460 px PNG cost about 58k characters.
# dir defaults to $TMPDIR/sim-shots. Never save shots with customer data inside the repo.
D=${3:-${TMPDIR:-/tmp}/sim-shots}
mkdir -p "$D/full"
sleep 1
xcrun simctl io booted screenshot "$D/full/$1.png" >/dev/null 2>&1 || { echo "no booted simulator"; exit 1; }
sips -Z ${2:-400} -s format jpeg -s formatOptions 50 "$D/full/$1.png" --out "$D/$1.jpg" >/dev/null
echo "$D/$1.jpg"
