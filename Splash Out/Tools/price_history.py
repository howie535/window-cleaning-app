#!/usr/bin/env python3
"""Work out each customer's price history from the yearly worksheets, for the app's price rise logic.

The app's own records start on 6 April 2026, so without this a customer with no rise logged is counted from
their first clean in the app. The worksheets go further back: a cell comment such as "£15 from here",
"£17 from today" or "£15 new price" marks a rise on the clean it started, and the clean dates show how long a
price has stood.

Reads the worksheets only (never writes to them), with the standard library, so openpyxl isn't needed.

Usage:
    python3 price_history.py IMPORT_JSON OUTPUT_FOLDER "Worksheet 2025-6.xlsx" "Worksheet 2026-7.xlsx" [...]

IMPORT_JSON is the app's import file (splash-out-import.json from convert_round_workbook.py). It gives each
customer's app ID, so the history lands on the right customer. Worksheets go oldest first; add 2024-5 in front
when it turns up.

Writes:
    OUTPUT_FOLDER/price-history.json         every customer's history, with names
    OUTPUT_FOLDER/price-history-app.json     the same with IDs only, built into the app and merged once on first open
    OUTPUT_FOLDER/price-history-report.txt   every rise found, the ones to check, customers not matched

Never write the output inside the app's git repository: it holds customer data.
"""
import datetime as dt
import html
import json
import re
import sys
import zipfile
from collections import Counter
from pathlib import Path

SCHEMA = 1
ROUND_SHEETS = ["Rhyl", "Abergele", "Llanddulas", "Llandudno"]
NAME, ADDR, PRICE = "B", "C", "D"
FIRST_CLEAN = 6          # column F = Clean 1, G = P1, and so on in pairs
EARLIEST = dt.date(2000, 1, 1)
RECORDS_START = dt.date(2026, 4, 6)   # the app's own records start here; older cleans come from the worksheets
DASHES = {"—", "–", "-", "--"}

# "£15 from here", "£17 from today", "£15 new price", "new price £15". One-off notes (front only, conservatory
# roof, gate locked) don't match.
RISE = [re.compile(r"£\s*(\d+(?:\.\d{1,2})?)\s*(?:a clean\s*)?(?:from\s+(?:here|today|now|this\s+clean|next))", re.I),
        re.compile(r"£\s*(\d+(?:\.\d{1,2})?)\s*new\s+price", re.I),
        re.compile(r"new\s+price\s*(?:of\s*)?£\s*(\d+(?:\.\d{1,2})?)", re.I)]


# ---------------------------------------------------------------- reading .xlsx with the standard library

def colnum(c):
    n = 0
    for ch in c:
        n = n * 26 + ord(ch) - 64
    return n


def excel_date(v):
    if isinstance(v, float) and 36000 < v < 60000:
        d = dt.date(1899, 12, 30) + dt.timedelta(days=int(v))
        return d if d >= EARLIEST else None
    return None


def read_workbook(path):
    """{sheet: {"cells": {(row, col): value}, "comments": {(row, col): text}}} for the round sheets."""
    z = zipfile.ZipFile(path)
    names = z.namelist()
    strings = []
    if "xl/sharedStrings.xml" in names:
        for si in re.findall(r"<si>(.*?)</si>", z.read("xl/sharedStrings.xml").decode(), re.S):
            strings.append(html.unescape("".join(re.findall(r"<t[^>]*>([^<]*)</t>", si))))
    book = z.read("xl/workbook.xml").decode()
    rels_xml = z.read("xl/_rels/workbook.xml.rels").decode()
    rels = {}
    for rel in re.findall(r"<Relationship [^>]*/>", rels_xml):
        rels[re.search(r'Id="([^"]+)"', rel).group(1)] = re.search(r'Target="([^"]+)"', rel).group(1)
    out = {}
    for tag in re.findall(r"<sheet [^>]*/>", book):
        name = html.unescape(re.search(r'name="([^"]+)"', tag).group(1))
        if name not in ROUND_SHEETS:
            continue
        target = rels[re.search(r'r:id="([^"]+)"', tag).group(1)]
        path_in_zip = target.lstrip("/") if target.startswith("/") else "xl/" + target
        xml = z.read(path_in_zip).decode()
        cells = {}
        for m in re.finditer(r'<c r="([A-Z]+)(\d+)"([^>]*?)(?:/>|>(.*?)</c>)', xml, re.S):
            col, row, attrs, inner = m.groups()
            if not inner:
                continue
            v = re.search(r"<v>([^<]*)</v>", inner)
            t = re.search(r't="(\w+)"', attrs)
            if t and t.group(1) == "s" and v:
                val = strings[int(v.group(1))]
            elif t and t.group(1) == "inlineStr":
                val = html.unescape("".join(re.findall(r"<t[^>]*>([^<]*)</t>", inner)))
            elif t and t.group(1) == "str" and v:
                val = html.unescape(v.group(1))
            elif v:
                try:
                    val = float(v.group(1))
                except ValueError:
                    val = v.group(1)
            else:
                continue
            cells[(int(row), colnum(col))] = val
        comments = {}
        sheet_rels = "xl/worksheets/_rels/" + path_in_zip.split("/")[-1] + ".rels"
        if sheet_rels in names:
            for rel in re.findall(r"<Relationship [^>]*/>", z.read(sheet_rels).decode()):
                tgt = re.search(r'Target="([^"]+)"', rel).group(1)
                if re.search(r"/comments\d*\.xml$", tgt) or re.match(r"comments\d*\.xml$", tgt.split("/")[-1]):
                    cpath = "xl/" + tgt.split("../")[-1]
                    cxml = z.read(cpath).decode()
                    for cm in re.finditer(r'<comment ref="([A-Z]+)(\d+)"[^>]*>(.*?)</comment>', cxml, re.S):
                        text = html.unescape("".join(re.findall(r"<t[^>]*>([^<]*)</t>", cm.group(3))))
                        if "Comment:" in text:          # threaded comment: the real text follows "Comment:"
                            text = text.split("Comment:", 1)[1]
                        comments[(int(cm.group(2)), colnum(cm.group(1)))] = " ".join(text.split())
        out[name] = dict(cells=cells, comments=comments)
    return out


# ---------------------------------------------------------------- one worksheet's customers

def norm(s):
    return re.sub(r"[^a-z0-9]", "", str(s or "").lower())


def money(v):
    return round(float(v), 2) if isinstance(v, (int, float)) else None


def rise_in(comment):
    for pattern in RISE:
        m = pattern.search(comment or "")
        if m:
            return round(float(m.group(1)), 2)
    return None


def read_customers(path, label):
    rows = []
    for sheet, data in read_workbook(path).items():
        cells, comments = data["cells"], data["comments"]
        max_row = max((r for r, _ in cells), default=0)
        max_col = max((c for _, c in cells), default=0)
        for r in range(2, max_row + 1):
            name = str(cells.get((r, colnum(NAME))) or "").strip()
            if not name:
                continue
            cleans = []
            slots = []      # every clean and dash in order, for bringing the cleans over
            for k, c in enumerate(range(FIRST_CLEAN, max_col + 1, 2)):
                d = excel_date(cells.get((r, c)))
                note = " / ".join(x for x in (comments.get((r, c)), comments.get((r, c + 1))) if x)
                raw = cells.get((r, c))
                if d:
                    slots.append(dict(kind="cleaned", date=d, paid=money(cells.get((r, c + 1))) or 0.0, note=note or None))
                elif isinstance(raw, str) and raw.strip() in DASHES:
                    slots.append(dict(kind="skipped", date=None, paid=0.0, note=note or None))
                if d:
                    cleans.append(dict(slot=k + 1, date=d, paid=money(cells.get((r, c + 1))), note=note))
                elif note and rise_in(note):
                    cleans.append(dict(slot=k + 1, date=None, paid=None, note=note))
            # a rise note can sit on the name or price cell too
            side = " / ".join(x for x in (comments.get((r, colnum(NAME))), comments.get((r, colnum(PRICE)))) if x)
            rows.append(dict(sheet=sheet, row=r, worksheet=label, name=name,
                             address=str(cells.get((r, colnum(ADDR))) or "").strip(),
                             price=money(cells.get((r, colnum(PRICE)))), cleans=cleans, side_note=side, slots=slots,
                             every_other=str(cells.get((r, colnum("E"))) or "").strip().upper() == "EO"))
    return rows


# ---------------------------------------------------------------- history for one customer across years

def usual(amounts):
    """The most common amount paid (ignoring £0, which means unpaid); None if there isn't one."""
    amounts = [a for a in amounts if a]
    return Counter(amounts).most_common(1)[0][0] if amounts else None


def history(years):
    """years: [(label, row or None)] oldest first. Returns (first_seen, changes, checks)."""
    changes, checks = [], []
    first_seen = None
    price_before = None            # list price at the end of the previous worksheet
    carried = None                 # a rise noted on the last, undated slot of the previous worksheet
    for label, row in years:
        if row is None:
            continue
        dated = [c for c in row["cleans"] if c["date"]]
        if dated and (first_seen is None or dated[0]["date"] < first_seen):
            first_seen = dated[0]["date"]
        noted_new = set()
        if carried and dated:
            new, note, from_label = carried
            old = (changes[-1]["new"] if changes else None) or price_before
            if new and (old is None or abs(old - new) >= 0.005):
                changes.append(dict(date=dated[0]["date"], old=old, new=new, source="comment",
                                    note=f"{note} (noted at the end of {from_label})", worksheet=label))
            noted_new.add(new)
        carried = None
        for i, c in enumerate(row["cleans"]):
            new = rise_in(c["note"])
            if new is None:
                continue
            date = c["date"] or next((d["date"] for d in row["cleans"][i + 1:] if d["date"]), None)
            if date is None:
                carried = (new, c["note"], label)     # starts on the first clean of the next worksheet
                continue
            if not new:
                continue                              # £0 means a free clean, not a price
            earlier = [d["paid"] for d in row["cleans"][:i] if d["date"]][-3:]
            old = (changes[-1]["new"] if changes and changes[-1]["date"] < date else None) or usual(earlier) or price_before
            if old is not None and abs(old - new) < 0.005:
                continue          # the note just confirms the price it already was
            changes.append(dict(date=date, old=old, new=new, source="comment", note=c["note"], worksheet=label))
            noted_new.add(new)
        side = rise_in(row["side_note"])
        if side is not None and side not in noted_new:
            checks.append(f"{label}: note \"{row['side_note']}\" on the name/price cell, with no clean to date it")
        # a change of list price between worksheets with no note to explain it
        if price_before is not None and row["price"] is not None and abs(price_before - row["price"]) >= 0.005 \
                and row["price"] not in noted_new and not any(abs(ch["new"] - row["price"]) < 0.005 for ch in changes):
            first_at_new = next((c for c in dated if c["paid"] is not None and abs(c["paid"] - row["price"]) < 0.005), None)
            if first_at_new:
                changes.append(dict(date=first_at_new["date"], old=price_before, new=row["price"], source="inferred",
                                    note=f"list price {pounds(price_before)} → {pounds(row['price'])}, first paid at "
                                         f"the new price on clean {first_at_new['slot']}", worksheet=label))
            else:
                checks.append(f"{label}: list price went {pounds(price_before)} → {pounds(row['price'])} "
                              f"but no clean was paid at {pounds(row['price'])}, so no date")
        # a lasting change in what was paid within one worksheet, with no note
        paid = [(c["date"], c["paid"]) for c in dated if c["paid"]]
        if row["price"] is not None and len(paid) >= 4 and row["price"] not in noted_new \
                and not any(abs(ch["new"] - row["price"]) < 0.005 and ch["worksheet"] == label for ch in changes):
            k = len(paid)
            while k > 0 and abs(paid[k - 1][1] - row["price"]) < 0.005:
                k -= 1
            before = [p for _, p in paid[:k]]
            if 1 <= k <= len(paid) - 2 and len(before) >= 2 and len(set(before[-2:])) == 1 and before[-1] < row["price"]:
                changes.append(dict(date=paid[k][0], old=before[-1], new=row["price"], source="inferred",
                                    note=f"paid {pounds(before[-1])} up to {paid[k - 1][0]:%-d %b %Y}, "
                                         f"{pounds(row['price'])} from then", worksheet=label))
        price_before = row["price"] if row["price"] is not None else price_before
    if carried:
        checks.append(f"{carried[2]}: \"{carried[1]}\" is noted for a clean not done yet, so it isn't a rise yet")
    changes = [ch for ch in changes if ch["new"]]     # £0 = free (Elie/Rebekah), not a price
    changes.sort(key=lambda ch: ch["date"])
    return first_seen, changes, checks


def pounds(v):
    if v is None:
        return "?"
    return f"£{v:,.0f}" if abs(v - round(v)) < 0.005 else f"£{v:,.2f}"


# ---------------------------------------------------------------- cleans for the app

def worksheet_visits(row):
    """A worksheet row's cleans and skips before the app's records start, by the same rules as
    convert_round_workbook.py: charged = what was paid, or the list price if unpaid (P = £0); dashes before the first
    clean and after the last are dropped; for every-other customers one dash between cleans is their off cycle
    (not due) and every second dash in a longer run is a skip; skips are dated halfway between the cleans either
    side, marked estimated."""
    slots = [dict(v) for v in row["slots"]]
    cleaned = [i for i, v in enumerate(slots) if v["kind"] == "cleaned"]
    if not cleaned:
        return []
    slots = slots[cleaned[0]:cleaned[-1] + 1]
    out, run, last = [], [], None
    for v in slots:
        if v["kind"] == "skipped":
            run.append(v)
            continue
        for j, sk in enumerate(run):
            kind = ("skipped" if j % 2 == 1 else "not_due") if row["every_other"] else "skipped"
            date = last + (v["date"] - last) * (j + 1) / (len(run) + 1) if last else v["date"]
            out.append(dict(date=date.isoformat(), kind=kind, list_price=row["price"] or 0, charged=0, paid=0,
                            note=sk["note"], date_estimated=True))
        run = []
        list_price = row["price"] or v["paid"] or 0
        # Unpaid on the worksheet (P = £0) counts as paid at the list price: those were all settled (Howie, 11 Nov 2026).
        charged = v["paid"] if v["paid"] > 0 else list_price
        out.append(dict(date=v["date"].isoformat(), kind="cleaned", list_price=list_price,
                        charged=charged, paid=charged, note=v["note"]))
        last = v["date"]
    return [x for x in out if dt.date.fromisoformat(x["date"]) < RECORDS_START]


# ---------------------------------------------------------------- main

def main():
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)
    reference = json.loads(Path(sys.argv[1]).read_text())["customers"]
    out_dir = Path(sys.argv[2])
    sheets = [Path(p) for p in sys.argv[3:]]
    years = [(p.stem.replace("Worksheet ", ""), read_customers(p, p.stem.replace("Worksheet ", ""))) for p in sheets]

    def find(rows, rnd, name, address):
        same_round = [r for r in rows if r["sheet"] == rnd]
        # name and address, then address alone (names get respelt: Britten/Britton), then name alone
        for pool in (same_round, rows):
            hits = [r for r in pool if norm(r["name"]) == norm(name) and norm(r["address"]) == norm(address)]
            if len(hits) == 1:
                return hits[0]
            hits = [r for r in pool if len(norm(address)) >= 6 and norm(r["address"]) == norm(address)]
            if len(hits) == 1:
                return hits[0]
            hits = [r for r in pool if norm(r["name"]) == norm(name)]
            if len(hits) == 1:
                return hits[0]
        return None

    records, report_rows, unmatched_in_app, visit_sets = [], [], [], []
    used = {label: set() for label, _ in years}
    for c in reference:
        found = []
        for label, rows in years:
            row = find(rows, c["round"], c["name"], c["address"])
            if row:
                used[label].add((row["sheet"], row["row"]))
            found.append((label, row))
        if not any(row for _, row in found):
            unmatched_in_app.append(c)
            continue
        first_seen, changes, checks = history(found)
        old_rows = [row for label, row in found[:-1] if row]
        visit_sets.append(dict(id=c["id"], visits=[v for row in old_rows for v in worksheet_visits(row)]))
        last = changes[-1] if changes else None
        if last and c.get("price") and abs(last["new"] - c["price"]) >= 0.005:
            checks.append(f"last rise found is to {pounds(last['new'])} but the price in the import file is {pounds(c['price'])}")
        records.append(dict(id=c["id"], round=c["round"], name=c["name"], address=c["address"],
                            first_seen=first_seen.isoformat() if first_seen else None,
                            changes=[dict(date=ch["date"].isoformat(), old=ch["old"], new=ch["new"], source=ch["source"])
                                     for ch in changes]))
        report_rows.append((c, first_seen, changes, checks))

    out_dir.mkdir(parents=True, exist_ok=True)
    # Former customers: on an older worksheet, cleaned at least once, gone by the newest one and not in the app.
    # They go into the app as Cancelled (no cleans, so no stats change), with when they were cleaned in a note.
    app_keys = {(norm(c["name"]), norm(c["address"])) for c in reference}
    former, seen = [], set()
    for label, rows in reversed(years[:-1]):
        for r in rows:
            dated = [c["date"] for c in r["cleans"] if c["date"]]
            key = (norm(r["name"]), norm(r["address"]))
            if (r["sheet"], r["row"]) in used[label] or not dated or key in seen:
                continue
            seen.add(key)
            if key in app_keys:
                continue          # already in the app
            visit_sets.append(dict(round=r["sheet"], name=r["name"], address=r["address"], visits=worksheet_visits(r)))
            former.append(dict(round=r["sheet"], name=r["name"], address=r["address"],
                               price=r["price"] or usual([c["paid"] for c in r["cleans"] if c["date"]]) or 0,
                               every_other=r["every_other"], first_clean=min(dated).isoformat(),
                               last_clean=max(dated).isoformat(), cleans=len(dated), worksheet=label))
    former.sort(key=lambda f: (ROUND_SHEETS.index(f["round"]), f["name"].lower()))

    (out_dir / "price-history.json").write_text(json.dumps(dict(
        schema=SCHEMA, generated=dt.date.today().isoformat(), worksheets=[label for label, _ in years],
        customers=records), indent=1, ensure_ascii=False))

    lines = [f"Price history from worksheets {', '.join(label for label, _ in years)} (made {dt.date.today():%-d %b %Y})", ""]
    noted = sum(1 for _, _, ch, _ in report_rows for x in ch if x["source"] == "comment")
    inferred = sum(1 for _, _, ch, _ in report_rows for x in ch if x["source"] == "inferred")
    lines += [f"Customers matched: {len(records)} of {len(reference)}",
              f"Rises from a note: {noted}", f"Rises worked out from the figures (check these): {inferred}",
              f"Customers with something to check: {sum(1 for r in report_rows if r[3])}",
              f"Customers in the app with no worksheet row: {len(unmatched_in_app)}",
              f"Former customers added as Cancelled: {len(former)}", ""]
    lines.append("== Rises worked out from the figures (check these)")
    for c, _, changes, _ in report_rows:
        for ch in changes:
            if ch["source"] == "inferred":
                lines.append(f"  {c['round']} · {c['name']}: {ch['date']:%-d %b %Y} {pounds(ch['old'])} → {pounds(ch['new'])}"
                             f" ({ch['worksheet']}: {ch['note']})")
    lines += ["", "== To check"]
    for c, _, _, checks in report_rows:
        for x in checks:
            lines.append(f"  {c['round']} · {c['name']}: {x}")
    lines += ["", "== In the app, no worksheet row found (counted from their first clean in the app as before)"]
    lines += [f"  {c['round']} · {c['name']} ({c['address']})" for c in unmatched_in_app]
    lines += ["", "== Worksheet rows not matched to an app customer"]
    for label, rows in years:
        for r in rows:
            if (r["sheet"], r["row"]) not in used[label] and r["cleans"]:
                lines.append(f"  {label} {r['sheet']} row {r['row']}: {r['name']} ({r['address']})")
    lines += ["", f"== Cleans brought over (before {RECORDS_START:%-d %b %Y}), by month: charged / paid"]
    by_month = {}
    for vs in visit_sets:
        for v in vs["visits"]:
            if v["kind"] == "cleaned":
                m = v["date"][:7]; a = by_month.setdefault(m, [0, 0.0, 0.0])
                a[0] += 1; a[1] += v["charged"]; a[2] += v["paid"]
    for m in sorted(by_month):
        n, ch, pd = by_month[m]
        lines.append(f"  {m}: {n} cleans, {pounds(ch)} / {pounds(pd)}")
    tot = [sum(a[i] for a in by_month.values()) for i in range(3)]
    unpaid = [(vs.get("id") or vs["name"], v) for vs in visit_sets for v in vs["visits"] if v["kind"] == "cleaned" and v["paid"] < v["charged"]]
    lines.append(f"  Total: {tot[0]} cleans, {pounds(tot[1])} charged, {pounds(tot[2])} paid; "
                 f"{sum(1 for vs in visit_sets for v in vs['visits'] if v['kind'] != 'cleaned')} skips and off-cycle visits")
    names = {c["id"]: c["name"] for c in reference}
    lines += [f"  Unpaid on the worksheet: {names.get(k, k)} {v['date']} {pounds(v['charged'])}" for k, v in unpaid]
    lines += ["", "== Former customers, added as Cancelled (no cleans brought over)"]
    lines += [f"  {f['round']} · {f['name']} ({f['address']}): {pounds(f['price'])}, {f['cleans']} cleans "
              f"{dt.date.fromisoformat(f['first_clean']):%-d %b %Y} to {dt.date.fromisoformat(f['last_clean']):%-d %b %Y}"
              for f in former]
    lines += ["", "== Every customer: price since (first clean on the worksheets) and rises"]
    for c, first_seen, changes, _ in report_rows:
        rises = "; ".join(f"{ch['date']:%-d %b %Y} {pounds(ch['old'])} → {pounds(ch['new'])}"
                          + (" (worked out)" if ch["source"] == "inferred" else "") for ch in changes) or "no rise"
        lines.append(f"  {c['round']} · {c['name']}: first clean {first_seen:%-d %b %Y} · {rises}" if first_seen
                     else f"  {c['round']} · {c['name']}: no cleans · {rises}")
    # The app's copy: IDs, dates and prices (no names) for current customers, plus the former customers. Copy it to
    # "Splash Out/PriceHistory2025.json" (git-ignored); the app merges it once on first open.
    (out_dir / "price-history-app.json").write_text(json.dumps(dict(
        schema=SCHEMA, worksheets=[label for label, _ in years],
        customers=[dict(id=r["id"], first_seen=r["first_seen"], changes=r["changes"]) for r in records],
        former=former, visits=[v for v in visit_sets if v["visits"]]), separators=(",", ":"), ensure_ascii=False))
    (out_dir / "price-history-report.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines[:8]))


if __name__ == "__main__":
    main()
