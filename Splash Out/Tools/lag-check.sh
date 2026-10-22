#!/bin/zsh
# Lag check for Splash Out: run after any new feature or code change, before installing on the phone.
# Builds for the Simulator, runs the self-test (which also times the round plan, stats and backup on the full data),
# then loads the full data and runs a scripted tour: every tab, one logged clean, then 12 seconds idle.
# Fails (exit 1) if anything goes over its time budget or the app rebuilds while idle.
# Budgets are Simulator times on a Mac; a phone is slower, so they're kept tight.

PROJECT="${0:A:h:h}"
SIM="3B332ACC-BF98-4DFA-8789-6E24F3183FEB"      # iPhone 17 Pro simulator
BUNDLE="com.splashout.Splash-Out"

FIRST_SCREEN_MS=200     # a tab's first appearance (cold)
SCREEN_MS=120           # any later rebuild of a screen
PLAN_MS=50              # round plan once warm
EXPORT_MS=200           # backup data gathered on the main thread
IDLE_REBUILDS=0         # rebuilds allowed while nothing is touched

cd "$PROJECT" || exit 2
# Timings only mean something on a quiet Mac. Warn if it's busy (load average well above the core count).
LOAD=$(sysctl -n vm.loadavg | awk '{print $2}')
CORES=$(sysctl -n hw.ncpu)
BUSY=$(/usr/bin/python3 -c "print(1 if $LOAD > $CORES * 1.5 else 0)")
[[ $BUSY == 1 ]] && echo "WARNING: the Mac is busy (load $LOAD on $CORES cores). Timings will be inflated; re-run when it's quiet before trusting a FAIL."
xcrun simctl boot $SIM 2>/dev/null
echo "Building..."
xcodebuild -scheme "Splash Out" -destination "id=$SIM" -derivedDataPath build -configuration Release build 2>&1 | grep -q "BUILD SUCCEEDED" \
  || { echo "BUILD FAILED"; exit 2; }
xcrun simctl terminate $SIM $BUNDLE 2>/dev/null
xcrun simctl install $SIM "build/Build/Products/Release-iphonesimulator/Splash Out.app"
D=$(xcrun simctl get_app_container $SIM $BUNDLE data)/Documents
[[ -f "$D/in.json" ]] || { echo "No full data file (in.json) in the Simulator app's Documents."; exit 2; }

echo "Self-test..."
rm -f "$D/selftest.txt"
xcrun simctl launch $SIM $BUNDLE -ImportFile in.json -SelfTest -ReportFile selftest.txt >/dev/null
for i in $(seq 1 120); do grep -q "SELFTEST:\|IMPORT FAILED" "$D/selftest.txt" 2>/dev/null && break; sleep 2; done
xcrun simctl terminate $SIM $BUNDLE 2>/dev/null
SELF=$(grep "SELFTEST:" "$D/selftest.txt")
FAILS=$(grep "^FAIL" "$D/selftest.txt")

echo "Tour with the full data..."
xcrun simctl launch $SIM $BUNDLE -ImportFile in.json >/dev/null; sleep 12; xcrun simctl terminate $SIM $BUNDLE 2>/dev/null
rm -f "$D/perf.txt"
xcrun simctl launch $SIM $BUNDLE -PerfLog -LagTour >/dev/null
for i in $(seq 1 30); do grep -q "MARK-END" "$D/perf.txt" 2>/dev/null && break; sleep 2; done
sleep 1
xcrun simctl terminate $SIM $BUNDLE 2>/dev/null
cp "$D/perf.txt" /tmp/splash-lag-perf.txt 2>/dev/null

# Put the Simulator back to customers only.
xcrun simctl launch $SIM $BUNDLE -ImportFile in.json -CustomersOnly >/dev/null; sleep 8; xcrun simctl terminate $SIM $BUNDLE 2>/dev/null

/usr/bin/python3 -I - "$D/selftest.txt" /tmp/splash-lag-perf.txt "$FIRST_SCREEN_MS" "$SCREEN_MS" "$PLAN_MS" "$EXPORT_MS" "$IDLE_REBUILDS" <<'PY'
import sys, re
selftest, perf, first_ms, screen_ms, plan_ms, export_ms, idle_max = sys.argv[1], sys.argv[2], *map(float, sys.argv[3:8])
problems, report = [], []
st = open(selftest).read() if selftest else ""
m = re.search(r"PERF plan first (\d+)ms then (\d+)ms, stats (\d+)ms, owed (\d+)ms", st)
if m:
    cold, warm, stats, owed = map(int, m.groups())
    report.append(f"Round plan: first {cold} ms, then {warm} ms (limit {plan_ms:.0f}); stats {stats} ms; owed {owed} ms")
    if warm > plan_ms: problems.append(f"round plan {warm} ms > {plan_ms:.0f}")
m = re.search(r"PERF export (\d+)ms", st)
if m:
    e = int(m.group(1)); report.append(f"Backup data (main thread): {e} ms (limit {export_ms:.0f})")
    if e > export_ms: problems.append(f"backup {e} ms > {export_ms:.0f}")
phase, seen, idle, worst = "START", set(), 0, {}
try: lines = open(perf).read().splitlines()
except OSError: lines = []
if not any("MARK-END" in l for l in lines): problems.append("the tour didn't finish (no END marker)")
for line in lines:
    parts = line.split()
    if len(parts) < 3: continue
    name, ms = parts[1], float(parts[2].rstrip("ms"))
    if name.startswith("MARK-"): phase = name[5:]; continue
    if phase == "IDLE": idle += 1
    limit = first_ms if name not in seen else screen_ms
    seen.add(name)
    key = (phase, name)
    worst[key] = max(worst.get(key, 0), ms)
    if ms > limit: problems.append(f"{name} {ms:.0f} ms during {phase.lower()} > {limit:.0f}")
for (phase, name), ms in sorted(worst.items()):
    report.append(f"{phase.lower():6} {name:10} worst {ms:6.1f} ms")
report.append(f"Rebuilds while idle: {idle} (limit {idle_max:.0f})")
if idle > idle_max: problems.append(f"{idle} rebuilds while idle")
print("\n".join(report))
print()
print("LAG CHECK: PASS" if not problems else "LAG CHECK: FAIL\n  " + "\n  ".join(problems))
sys.exit(1 if problems else 0)
PY
LAG=$?
[[ $LAG -ne 0 && $BUSY == 1 ]] && echo "(Mac was busy: treat this FAIL as unconfirmed and re-run when quiet.)"
echo "$SELF"
[[ -n "$FAILS" ]] && echo "$FAILS"
[[ $LAG -eq 0 && "$SELF" == *"ALL"* ]] && exit 0 || exit 1
