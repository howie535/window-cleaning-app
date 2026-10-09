# Next steps

Where things stand: all seven build stages in `SPEC.md` are in place. The app holds the customer database only (addresses, prices, notes). Cleaning history, payments and the diary start empty and get filled with test data before the switchover.

## 1. iPad build (landscape first)

The iPad is where the round spreadsheet is used today, in landscape, so this build is worth doing properly and should be done before the switchover. The app already runs on iPad (top tab bar, sidebar toggle, four-column Today tiles, Customers search/filter/reorder, Diary calendar with wider cells), but it has only been checked in portrait. Roughly 2 to 3 sessions:

- **Landscape check of every screen** on a real iPad or a hand-rotated Simulator (the Simulator tools used so far can't rotate the device).
- **Two-column Round and Customers.** List on the left, customer detail or logging panel on the right (`NavigationSplitView`), so working down the round doesn't push full screens.
- **Today and Weekly in landscape:** tiles and the chart side by side.
- **Sheet sizing.** Record payment, Add clean and Place in round as centred, medium-sized sheets rather than full-screen.
- **Keyboard shortcuts** for a keyboard case: new customer, search, move between tabs.
- **Larger tap targets** on the Round and Owed lists if the iPad is used on a ladder or in the van.
- **Weekly and Tax Year tables** laid out to use the extra width.

Nothing in the data model needs to change for any of this.

## 2. Switchover checklist (target 6 April 2027)

"Switchover" means the day the app replaces your round spreadsheet as the place you record everything. The aim is that nothing is lost and you trust the numbers before you stop using the spreadsheet. In order:

**Now to March (can be done any time, no rush)**
1. **Enrol in the paid Apple Developer Program.** This unlocks iCloud sync between your iPhone and iPad. In Xcode, add the iCloud (CloudKit) capability, then the app's database is switched from "this device only" to "iCloud". Test it: add a customer on the iPhone, check it appears on the iPad.
2. **Add a Git remote** (a private copy of the code on GitHub). One-off, about 10 minutes. See below if not done yet.
3. **Fill in test data** (fake cleans, payments, skips, a holiday in the diary, a tip). Work out a few totals by hand and check Weekly, Tax Year, Money Owed, Price Rise and Frequent Skips agree. Then clear the test history (Settings > Clear all cleaning history) so the customers are left alone.
4. **Check prices.** Look through Customers for any with a £0 price.

**Last week of March**
5. **Final tidy of the spreadsheet** so its customer list and prices are correct, then re-run `Tools/convert_round_workbook.py` to produce a fresh import file.
6. **Import it** (Settings > Import round data). This replaces everything in the app. A backup is saved automatically first.
7. **Check the figures** against the acceptance figures in `SPEC.md` section 7 (customer counts, round value, money owed).

**From 6 April**
8. **Parallel run, two weeks:** record every clean in the app AND keep the spreadsheet going. At the end of each week compare the weekly totals and money owed. If they match, carry on; if not, find out why before going further.
9. **Stop using the spreadsheet** once two weeks match.
10. **Weekly backup** for the first month: Settings > Export backup, saved to OneDrive.

## 3. Sync notes (for when iCloud is switched on)

- **Speed:** CloudKit sync is push-driven, not a constant stream. Changes normally show up on the other device within seconds to a minute when both are online, but Apple doesn't guarantee a time, and it can lag in Low Power Mode or with a weak connection. Edits made offline sync when the device is back online.
- **Same record on two devices at once:** the last change wins, so avoid editing the same customer on both at the same moment.
- **Settings row:** each device creates its own settings row on first launch. Before sync is switched on, the app needs to keep only one (and merge crews/team) or the devices will each end up with a copy.
- **Fresh install** starts with no customers, crews or team. Add the team in Settings first, then crews, then the usual week.

## 4. Known loose ends

- Landscape (checked on an iPad Pro 11 in the Simulator: Today, Round, Customers): everything works and is usable. Today is good (five tiles across, full-width chart). Round and Customers are a single very wide column, with the price or area far from the name. That is the case for the two-column layout in section 1. Diary, Owed, More and the sheets haven't been checked in landscape yet.
- Record payment: a brief red "more than is owed" message can flash while the sheet closes after saving a partial payment. Harmless, but untidy.
- Customers priced at £0 aren't flagged anywhere; look through the list for them before the switchover.
