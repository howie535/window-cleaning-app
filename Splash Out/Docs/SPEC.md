# Splash Out app: specification for replacing the round spreadsheet

The app takes over from the spreadsheet as the one record of the round. This document holds every rule the spreadsheet (`Splash Out Round.xlsx`) worked out, so the app can do the same jobs without anyone needing the spreadsheet open.

Build from this file one section at a time. Where the app already does something (customers, clean logs, WhatsApp, route ordering, CSV import), extend it rather than replacing it.

## 1. The switchover

- **Switch at the start of a tax year: 6 April 2027.** Then no tax year is split across two systems.
- Until then the spreadsheet stays the record. Re-run the converter (`Tools/convert_round_workbook.py`) at the switch for a final, complete import.
- **Parallel check:** for the first two weeks, also keep the spreadsheet going. At the end, check that the app's Weekly, Money Owed and Tax Year figures match it to the penny. Then stop using the spreadsheet.
- Keep the spreadsheet afterwards as a read-only archive. Don't delete it.

### Must be done before the switch

1. **Backup and sync.** The data currently lives only on the phone. Use SwiftData with CloudKit sync, so it's backed up to iCloud and the same data appears on iPhone and iPad. Also add a manual export (the import file format, see §6) saved to Files/OneDrive, as a second backup.
2. **iPad.** The round is worked from an iPad in landscape during the day, so every screen must work well on iPad in landscape, with large tap targets. Phone support stays.
3. **A remote for the code.** The git repo has no remote. Push it to a private GitHub repo, or the code has no backup either.
4. **Who logs in.** Today the iPad is shared, and Howie, Dad and Rebekah all use the one spreadsheet. Simplest: one Apple ID on the shared iPad and Howie's phone, all syncing through CloudKit's private database. Separate Apple IDs would need CloudKit sharing, so treat that as later work.

## 2. Data model

Extend the existing models. Field names are suggestions.

### Customer (extends the existing `Customer`)

| Field | Type | Notes |
|---|---|---|
| id | UUID | Stable. The import supplies it. |
| sequence | Int | Position in round order (the "conveyor belt"). Drives Next Up. Reorderable by dragging. |
| round | String | Rhyl, Abergele, Llanddulas, Llandudno (editable list). |
| area | String | Town or area, e.g. Kinmel Bay, Craig-y-Don. |
| status | enum | active, not_started, paused, leaving, cancelled |
| name, address, phone | String | phone is blank on import; fill in from Contacts later. |
| price | Decimal | What the customer is charged per clean. |
| priceSince | Date? | When the current price started. Blank means before records began. |
| everyOther | Bool | "EO": cleaned every other time round. |
| frontOnly | Bool | |
| contact | enum | whatsapp (default), ring |
| payMethod | enum? | cash, bacs, standing_order |
| notes | [String] | Free notes, including the spreadsheet's cell comments. |
| latitude, longitude | Double? | Existing fields. |

Replace the existing `frequencyWeeks` and `isDue` logic with sequence plus everyOther (§4.6). The round is worked in order, not by due date.

### Visit (extends the existing `CleanLog`)

| Field | Type | Notes |
|---|---|---|
| date | Date | |
| kind | enum | cleaned, skipped (one-off cancellation), not_due (an EO customer's off cycle) |
| listPrice | Decimal | The customer's price on that date. |
| charged | Decimal | What the clean is worth. Normally listPrice. More for extras (conservatory roof, gutters), less for front only. |
| paid | Decimal | 0 until paid. |
| paidDate | Date? | When payment arrived. Blank on import. |
| note | String? | |

- A visit is **unpaid** when `kind == cleaned` and `paid < charged`.
- The existing over/underpayment balance stays.

### PriceChange

`customer`, `date`, `oldPrice`, `newPrice`, `reason` (rise, correction, new quote). Changing a customer's price creates one, and updates `price` and `priceSince`.

### Crew and WorkDay

- **Crew:** a name, its members, and a day target in £. Valid crews:

| Crew | Day target |
|---|---|
| Howie + Dad | £400 |
| Howie + Rebekah | £300 |
| Dad + Rebekah | £300 |
| Howie alone | £300 |
| Dad alone | £250 |

  All three never work together, and Rebekah never works alone.
- **WorkDay** (the old Diary), optional: `date`, `dayOff` (holiday or illness), `crew` (override), `note`. Only days that differ from the usual week are stored.

### Settings

| Setting | Default |
|---|---|
| Usual week: crew per weekday | Mon Howie + Dad, Tue Howie + Dad, Wed Howie + Rebekah, Thu–Sun none |
| Extra-day crew | Howie + Dad |
| Minimum houses for a day to count as worked | 5 |
| Next Up overbook allowance | 10% |
| Next Up: hide customers cleaned within | 3 weeks (8 for every-other customers) |
| Price rise | date (blank = none planned), 10%, delay rule 12 months, due after 24 months |
| Records start | 6 April 2026 |

### Tip

`date`, `name`, `amount`. Tips are never counted as income anywhere.

## 3. Logging the round (the screens used every day)

These replace typing dates into the spreadsheet, so they must be fast with wet hands.

- **Today's round:** the Next Up list for today (§4.6). Tapping a customer gives one-tap options:
  - **Cleaned & paid**
  - **Cleaned, not paid**
  - **Skipped**
  - **Not due (EO)**
  - **Cleaned + extra**, which asks for the extra £ and a note
- **Defaults:** the date defaults to today. The amount defaults to the price, or the front-only price. Undo is available for 10 seconds.
- **Record a payment:** from Money Owed or the customer page, mark one or more unpaid visits paid. You can enter a single lump sum, which pays the oldest visits first. Cash, BACS and SO are all handled the same way.
- **Customer page:** details, visit history newest first, balance, price history, notes, and the WhatsApp or Ring button.
- **New customer:** choose where they go in round order (after which customer), then status `not_started` until their first clean.

## 4. Rules and calculations

### 4.1 Work value

Work for any period = Σ `charged` over visits with `kind == cleaned` in that period, whether paid or not. "Paid" and "not yet paid" are shown separately where useful. This matches the spreadsheet's Weekly Data exactly: a payment is counted at what was paid, and an unpaid clean at the customer's price.

### 4.2 Tax year

A date belongs to tax year Y–(Y+1) when it falls on or after 6 April Y and before 6 April Y+1. Every total can be shown for any tax year. Months run April (from the 6th), May … March, then April (to the 5th).

### 4.3 Working days and weekly target

- **A worked day** is any date with at least *minimum houses* (5) cleaned visits. Nobody has to record it.
- **Usual week target** = the sum of the usual week's day targets (£400 + £400 + £300 = £1,100). It does not change with the crew.
- **For a past week:**
  - *usualDays* = usual-pattern days not marked dayOff
  - *base* = the sum of their usual targets
  - *worked* = the number of worked days in the week
  - *target* = 0 if worked = 0 (a week off), otherwise base + max(0, worked − usualDays) × extra-day crew's target
- **What follows from that:**
  - A rained-off Monday caught up on Thursday is still a three-day week, £1,100.
  - A fourth day adds £400.
  - A logged holiday day lowers the target.
- **The current week** uses the same rule for days up to and including today.

### 4.4 Day target (for booking, Today and Next Up)

- A WorkDay crew override sets the day target to that crew's target.
- Otherwise it's the usual crew for that weekday.
- A worked day outside the usual pattern uses the extra-day crew.
- A dayOff is 0.

### 4.5 Ahead or behind (Today)

**Ahead/behind = tax-year-to-date work − (sum of weekly targets for completed weeks this tax year + this week's targets for days up to today).**

### 4.6 Next Up (who's next)

1. **Pointer:** the customer with the latest cleaned visit date. On a tie, the one furthest along in sequence.
2. **Order:** customers in sequence order starting just after the pointer, wrapping round to the start.
3. **Who's included:** status `active` or `leaving`, and not cleaned in the last 3 weeks. For every-other customers it's 8 weeks: they're left out if their last visit was cleaned within 8 weeks, or was `not_due` within the last 3 weeks.
4. **Days to fill:** the next 20 working days from today. That's the usual pattern minus dayOff days, plus any future WorkDay with a crew.
5. **How each day fills:** to day target × (1 + overbook), using a running total of the customers' prices.
6. **Shown for each customer:** day, area, name, address, price, EO, Ring/WhatsApp, front only, last clean, anything owed, notes.

### 4.7 Round value and cycle length

- **Round value per cycle** = Σ price over customers with status active, leaving or not_started. Every-other customers count at half.
- **Cycle length (weeks)** = round value ÷ average weekly work over the last 8 weeks that had a target.

### 4.8 Money owed

- **The list:** every unpaid cleaned visit, grouped by customer, oldest first. It shows £ owed, number of cleans, oldest date, weeks owed and pay method.
- **Total:** shown on Today.

### 4.9 Frequent skips

- **Look at:** each active or leaving customer's last 6 visits since their first clean.
- **Count:** `skipped` visits. Every-other customers' `not_due` visits don't count.
- **Flag:** two or more puts them on the list.

The app records skips explicitly, so this is more reliable than the spreadsheet's version.

### 4.10 Price rise

- **New price** = round(price × (1 + percent)) to the nearest pound, with exactly 50p going down. £15 → £16, £12 → £13, £20 → £22.
- **Takes effect on** the rise date. If the customer's priceSince is less than 12 months before the rise date, it takes effect 12 months after priceSince instead.
- **Doesn't apply** if priceSince is on or after the rise date.
- **When it applies,** create a PriceChange and update price. Don't change past visits.
- **Preview screen:** every active customer with their current price, new price, effective date and pay method, plus the uplift per cycle. Every-other customers count at half.
- **Rise due** = active or leaving, price > 0, and priceSince blank or more than 24 months ago.

### 4.11 Checks

- **Paying under price:** the last cleaned visit was paid, but for less than listPrice, and the customer isn't front only.
- **Data issues:** visits with impossible dates. The import leaves these out and reports them.

### 4.12 Other figures on Today

- **New this tax year:** first cleaned visit this tax year. For 2026-27 only, ignore first cleans before 18 May 2026, because records start in April 2026.
- **Lost this tax year:** status cancelled, with the last clean in this tax year.
- **Skip rate:** skipped ÷ (skipped + cleaned) over each customer's last 6 visits.
- **This month:** work so far this calendar month.

### 4.13 Crew averages

For days with a known crew (a WorkDay override, or the usual crew): average £ per day, houses per day and £ per house, by crew. This replaces the averages on the spreadsheet's Settings sheet.

## 5. Screens

| Screen | Purpose |
|---|---|
| Today | Tiles: this week (£ v target, houses), today (£ v day target, crew), ahead/behind, money owed, this month, round value and cycle, customers, new v lost, skip rate, rises due. Plus a 12-week bar chart against target. |
| Round / Next Up | §3 and §4.6. The working screen. |
| Customers | Search and filter by round, area and status. Drag to reorder. |
| Money Owed | §4.8, with record-payment. |
| Weekly | One row per week from records start: work, houses, target, days worked. Green when work ≥ target, amber when within 10% below, red when lower. |
| Tax Year | Pick a year. Months with work, paid, not yet paid, cleans, extras and average per week, plus totals by round. Export to CSV/PDF for Self Assessment. |
| Frequent Skips | §4.9 |
| Price Rise | §4.10 |
| Checks | §4.11 |
| Diary | Optional WorkDay entries: day off, crew override, note. |
| Settings | Everything in §2 Settings, plus export and import. |
| Tips | List and add. Total shown; never counted as income. |

All dates display as d-MMM (6-Oct), or d-MMM-yy where the year matters. All money is £, shown to the pound unless pence matter.

## 6. Import file

`splash-out-import.json`, produced by `Tools/convert_round_workbook.py`. Never commit it: it holds customer data.

```
{
  "schema": 1,
  "generated_at": "2026-10-08T17:50:03",
  "source": "Splash Out Round.xlsx",
  "settings": {
    "crews": [{"name": "Howie + Dad", "members": ["Howie", "Dad"], "day_target": 400.0}, ...],
    "usual_week": {"monday": "Howie + Dad", ..., "thursday": null, ...},
    "extra_day_crew": "Howie + Dad",
    "min_houses_for_working_day": 5,
    "overbook": 0.1,
    "next_up_hide_weeks": 3,
    "next_up_hide_weeks_every_other": 8,
    "price_rise": {"date": null, "percent": 0.1, "rounding": "nearest_pound_half_down", "delay_months": 12, "due_after_months": 24},
    "records_start": "2026-04-06"
  },
  "customers": [{
    "id": "uuid", "sequence": 1, "round": "Rhyl", "area": "Bodelwyddan", "status": "active",
    "name": "...", "address": "...", "phone": null, "price": 30.0, "price_since": "2026-04-21" | null,
    "every_other": false, "front_only": false, "contact": "whatsapp" | "ring", "pay_method": "so" | "bacs" | "cash" | null,
    "notes": ["..."],
    "visits": [{"date": "2026-04-21", "kind": "cleaned" | "skipped" | "not_due", "slot": 1,
                "list_price": 30.0, "charged": 30.0, "paid": 30.0, "note": null, "date_estimated": true?}]
  }],
  "diary": [{"date": "2026-09-14", "day_off": true, "crew": ["Howie", "Dad"] | null, "note": "Holiday"}],
  "tips": [{"date": "...", "name": "...", "amount": 5.0}]
}
```

### Import rules

- **Replace, don't merge.** An import wipes and reloads customers, visits, diary, tips and settings. Show a confirmation first, and take an automatic export backup.
- **charged:** on import, a paid visit's charged equals what was paid. The spreadsheet didn't record the reason for a difference, so this avoids creating false debts or credits. An unpaid visit is charged at list price.
- **Skipped and not_due dates** are estimated. The spreadsheet records a dash with no date. `date_estimated` marks these.
- **Visits** with impossible dates (e.g. 1900) are left out and listed in `import-report.txt`.
- **Cell comments** from the spreadsheet arrive as visit notes or customer notes.

## 7. Acceptance figures

An import of the October 2026 snapshot must give these figures in the app, the same as the workbook and `import-report.txt`:

| Check | Expected |
|---|---|
| Customers | 372 (360 active, 2 not started, 1 paused, 1 leaving, 8 cancelled) |
| Round value per cycle | £5,885.50 |
| Money owed | £2,623 over 157 cleans |
| Tax year 2026-27 to 7 Oct | work £23,961, paid £21,338, 1,436 cleans |
| Week of 5 Oct 2026 | work £1,140, target £1,100, 3 days worked |
| Week of 14 Sep 2026 | week off, target £0 |
| Week of 11 May 2026 | target £1,200 (Wed holiday, Thursday worked as an extra day) |
| Crew averages from the diary | Howie + Dad £367/day over 27 days, Howie + Rebekah £294 over 21 |
| Price rise preview at 6 Apr 2027 (10%) | about +£539 a cycle |

## 8. Build order

1. Backup and sync (CloudKit) and a code remote. Nothing else until data is safe.
2. Data model changes (§2) and the importer (§6). Import the snapshot and check §7.
3. Logging the round and recording payments (§3).
4. Next Up (§4.6) and Money Owed (§4.8).
5. Today, Weekly and Tax Year (§4.1–4.5, §4.7, §4.12). Check §7 again.
6. Price Rise, Frequent Skips, Checks, Diary, Tips, Settings.
7. iPad landscape polish, then a test switchover with a fresh import.

## 9. Open points

- **Phone numbers** aren't in the spreadsheet. Fill them from Contacts or WhatsApp after import (the app already has a contact picker).
- **iOS 26.5:** the deployment target is iOS 26.5. Confirm the iPad and phones are on it.
- **Separate logins:** whether Dad and Rebekah ever need their own logins (CloudKit sharing).
