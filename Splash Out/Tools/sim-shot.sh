#!/bin/zsh
# Simulator screenshot with a small copy to read (full-size images bloat the conversation).
# usage: Tools/sim-shot.sh <name> [size] [dir]
#   full size: <dir>/full/<name>.png   small copy (read this one): <dir>/<name>.png
# dir defaults to $TMPDIR/sim-shots. Never save shots with customer data inside the repo.
D=${3:-${TMPDIR:-/tmp}/sim-shots}
mkdir -p "$D/full"
sleep 1
xcrun simctl io booted screenshot "$D/full/$1.png" >/dev/null 2>&1 || { echo "no booted simulator"; exit 1; }
cp "$D/full/$1.png" "$D/$1.png" && sips -Z ${2:-460} "$D/$1.png" >/dev/null
echo "$D/$1.png"
