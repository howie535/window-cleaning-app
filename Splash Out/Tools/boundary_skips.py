#!/usr/bin/env python3
"""Recover the skips lost where one yearly worksheet ends and the next begins.

Both imports treated each worksheet on its own: dashes after a customer's last clean on 2025-6 were dropped as
"left", and dashes before their first clean on 2026-7 were dropped as "not started yet". For a customer cleaned on
both sheets those dashes are real skips (or every-other off cycles), so March to May 2026 showed almost none.

This joins the two sheets per customer: the dashes after the last 2025-6 clean and before the first 2026-7 clean are
one run, given meaning by the usual rules (every-other: every second dash is a skip, the rest not due; otherwise all
skips) and dated evenly between the two cleans, marked estimated.

Usage:
    python3 boundary_skips.py IMPORT_JSON OUTPUT_FOLDER "Worksheet 2025-6.xlsx" "Worksheet 2026-7.xlsx"

Writes OUTPUT_FOLDER/boundary-skips-app.json (IDs only, copy to "Splash Out/PriceHistory2026Skips.json", git-ignored;
the app merges it once on first open) and OUTPUT_FOLDER/boundary-skips-report.txt. Never write inside the repo.
"""
import datetime as dt
import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from price_history import read_customers, norm  # noqa: E402


def find(rows, rnd, name, address):
    same_round = [r for r in rows if r["sheet"] == rnd]
    for pool in (same_round, rows):
        for test in (lambda r: norm(r["name"]) == norm(name) and norm(r["address"]) == norm(address),
                     lambda r: len(norm(address)) >= 6 and norm(r["address"]) == norm(address),
                     lambda r: norm(r["name"]) == norm(name)):
            hits = [r for r in pool if test(r)]
            if len(hits) == 1:
                return hits[0]
    return None


def gap_visits(old, new, price):
    cleaned_old = [i for i, v in enumerate(old["slots"]) if v["kind"] == "cleaned"]
    cleaned_new = [i for i, v in enumerate(new["slots"]) if v["kind"] == "cleaned"]
    if not cleaned_old or not cleaned_new:
        return []
    tail = [v for v in old["slots"][cleaned_old[-1] + 1:] if v["kind"] == "skipped"]
    head = [v for v in new["slots"][:cleaned_new[0]] if v["kind"] == "skipped"]
    run = tail + head
    a, b = old["slots"][cleaned_old[-1]]["date"], new["slots"][cleaned_new[0]]["date"]
    if not run or not (a and b) or b <= a:
        return []
    every_other = new["every_other"]
    out = []
    for j, sk in enumerate(run):
        kind = ("skipped" if j % 2 == 1 else "not_due") if every_other else "skipped"
        date = a + (b - a) * (j + 1) / (len(run) + 1)
        out.append(dict(date=date.isoformat(), kind=kind, list_price=price or 0, charged=0, paid=0,
                        note=sk.get("note"), date_estimated=True))
    return out


def main():
    if len(sys.argv) != 5:
        print(__doc__)
        sys.exit(1)
    reference = json.loads(Path(sys.argv[1]).read_text())["customers"]
    out_dir = Path(sys.argv[2])
    old_rows = read_customers(Path(sys.argv[3]), "2025-6")
    new_rows = read_customers(Path(sys.argv[4]), "2026-7")
    sets, lines, months = [], [], Counter()
    for c in reference:
        old, new = find(old_rows, c["round"], c["name"], c["address"]), find(new_rows, c["round"], c["name"], c["address"])
        if not (old and new):
            continue
        visits = gap_visits(old, new, c.get("price"))
        if not visits:
            continue
        sets.append(dict(id=c["id"], visits=visits))
        for v in visits:
            months[(v["date"][:7], v["kind"])] += 1
        lines.append(f"  {c['round']} · {c['name']}: " + ", ".join(f"{v['date']} {v['kind']}" for v in visits))
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "boundary-skips-app.json").write_text(json.dumps(
        dict(schema=1, generated=dt.date.today().isoformat(), customers=[], visits=sets), separators=(",", ":"), ensure_ascii=False))
    head = [f"Skips recovered between the 2025-6 and 2026-7 worksheets (made {dt.date.today():%-d %b %Y})",
            f"Customers: {len(sets)}; visits: {sum(len(s['visits']) for s in sets)}", "", "== By month"]
    head += [f"  {m} {k}: {n}" for (m, k), n in sorted(months.items())]
    (out_dir / "boundary-skips-report.txt").write_text("\n".join(head + ["", "== Customers"] + lines) + "\n")
    print("\n".join(head))


if __name__ == "__main__":
    main()
