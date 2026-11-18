#!/bin/zsh
# Swipe check for Splash Out: does a full swipe on the Round take away only the swiped row (like Mail)?
# Loads the full data, then a UI test does three real full swipes on today's Round while the app's RowProbe
# (-RowProbe) records rows leaving and coming back. FAIL if any other row disappears and reappears within
# 1.5 s of a swipe for 30 ms or more (the blink). Puts the Simulator back to the full data at the end.

PROJECT="${0:A:h:h}"
SIM="3B332ACC-BF98-4DFA-8789-6E24F3183FEB"      # iPhone 17 Pro simulator
BUNDLE="com.splashout.Splash-Out"
cd "$PROJECT" || exit 2
xcrun simctl boot $SIM 2>/dev/null
D=$(xcrun simctl get_app_container $SIM $BUNDLE data 2>/dev/null)/Documents
[[ -f "$D/in.json" ]] || { echo "No full data file (in.json) in the Simulator app's Documents."; exit 2; }

echo "Loading the full data..."
xcrun simctl terminate $SIM $BUNDLE 2>/dev/null
xcrun simctl launch $SIM $BUNDLE -ImportFile in.json >/dev/null; sleep 12; xcrun simctl terminate $SIM $BUNDLE 2>/dev/null
rm -f "$D/rows.txt"

echo "Swiping (UI test)..."
xcodebuild test -scheme "Splash Out" -destination "id=$SIM" -derivedDataPath build-uitest -parallel-testing-enabled NO \
  -only-testing:"Splash OutUITests/SwipeBlinkUITests/testNotPaidFromHalfSwipe" -only-testing:"Splash OutUITests/SwipeBlinkUITests/testFullSwipePaid" > /tmp/splash-swipe-test.log 2>&1
TEST=$?
[[ $TEST -ne 0 ]] && { grep -E "error|failed|Failing" /tmp/splash-swipe-test.log | head -8; }
D=$(xcrun simctl get_app_container $SIM $BUNDLE data 2>/dev/null)/Documents   # look again: the test run can move it

/usr/bin/python3 -I - "$D/rows.txt" <<'PY'
import sys
try: lines = [l.split(" ", 2) for l in open(sys.argv[1]).read().splitlines()]
except OSError: print("SWIPE CHECK: FAIL\n  no rows.txt (the test never reached the Round)"); sys.exit(1)
events = [(float(t), e, n) for t, e, n in lines]
swipes = [(t, n) for t, e, n in events if e == "swipe"]
blinks, edge = [], []
for st, swiped in swipes:
    gone = {}
    for t, e, n in events:
        if t < st or t > st + 1.5 or n == swiped: continue
        if e == "disappear": gone[n] = t
        elif e == "appear" and n in gone:
            ms = int((t - gone.pop(n)) * 1000)
            # One frame (under ~30 ms) is a row at the screen edge being reused as the list shifts: not visible.
            (blinks if ms >= 30 else edge).append(f"{n} vanished for {ms} ms after swiping {swiped}")
print(f"Swipes: {len(swipes)}")
if edge: print(f"Edge-of-screen row reuses (one frame, not visible): {len(edge)}")
print("SWIPE CHECK: PASS" if swipes and not blinks else "SWIPE CHECK: FAIL\n  " + "\n  ".join(blinks or ["no swipe was logged"]))
sys.exit(0 if swipes and not blinks else 1)
PY
RESULT=$?
xcrun simctl boot $SIM 2>/dev/null
xcrun simctl terminate $SIM $BUNDLE 2>/dev/null
xcrun simctl launch $SIM $BUNDLE -ImportFile in.json >/dev/null; sleep 12; xcrun simctl terminate $SIM $BUNDLE 2>/dev/null
exit $RESULT
