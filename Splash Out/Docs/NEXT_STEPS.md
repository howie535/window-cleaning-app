# Next steps

Where things stand: all seven build stages in `SPEC.md` are in place. The app holds the customer database only (addresses, prices, notes). Cleaning history, payments and the diary start empty and get filled with test data before the switchover.

## 1. iPad: later build

The app is already universal. It runs on iPad today with the tab bar across the top (with a sidebar toggle), the Today tiles in four columns, and Customers search, filters and drag-to-reorder. That is usable as it stands. The bigger iPad build is optional polish, roughly 2 to 3 sessions of work:

- **Two-column Round and Customers.** List on the left, customer detail on the right (`NavigationSplitView`), so tapping a customer doesn't push a full screen.
- **Landscape pass.** Check every screen in landscape. Not yet done: the Simulator tools used so far can't rotate the device. Do it on a real iPad or by rotating the Simulator by hand.
- **Sheet sizing.** Record payment, Add clean and Place in round as centred, medium-sized sheets rather than full-screen.
- **Keyboard shortcuts.** For use with a keyboard case: new customer, search, move between tabs.
- **Larger tap targets** on the Round and Owed lists if the iPad is used on a ladder or in the van.
- **Weekly and Tax Year tables** wider layouts that use the extra width.

Nothing in the data model needs to change for any of this.

## 2. Before the switchover (target 6 April 2027)

1. **Paid Apple Developer enrolment**, then add iCloud (CloudKit) and Background Modes > Remote notifications in Xcode. Flip `Persistence.makeContainer` from `cloudKitDatabase: .none` to the private database. Test sync on a real iPhone and iPad (add on one, see it on the other).
2. **Don't promote the CloudKit schema to Production** until after the parallel check. Production schemas can't have fields removed or renamed.
3. **Git remote.** There is none, so the code and history exist only on this Mac. Add a private remote before the switchover.
4. **Test data.** Fill in a few weeks of fake cleans, payments, skips, diary days and tips, then confirm Weekly, Tax Year, Money Owed, Price Rise and Frequent Skips all calculate what you expect by hand.
5. **Parallel run.** Use the old round sheet and the app side by side for the first two weeks and compare weekly totals.
6. **Final import.** On the day, re-run `Tools/convert_round_workbook.py` against the latest sheet and do one full import (Settings > Import round data). The app takes an automatic backup before replacing anything.
7. **Backups.** Export a backup from Settings (saved to Files/OneDrive) at the end of each week for the first month.
8. **Acceptance figures** to match at the final import are in `SPEC.md` section 7.

## 3. Known loose ends

- Two Rhyl customers have a £0 price. Check them in Checks > Data issues.
- Record payment, Diary, Tips, Checks and Settings screens have been tested by the automated self-test but haven't all been looked at by eye.
