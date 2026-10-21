import Foundation
import SwiftData

/// The app's version and what changed in each one (Settings > What's new).
enum ChangeLog {
    struct Release: Identifiable {
        var version: String
        var date: String
        var changes: [String]
        var id: String { version }
    }

    static let releases: [Release] = [
        Release(version: "1.2", date: "October 2026", changes: [
            "Faster: the daily backup and calendar update now run in the background a few seconds after opening, and screens read the visit history in one go.",
            "Stats cards are all the same size.",
            "Price Rise is now a simple list: every customer's last price rise date (or No date logged), oldest first. Change a price on the customer's page; a higher price is logged as a rise.",
            "Customers page shows the groups under headings. Press and drag a customer into another group; press and hold for Start a new group after, Join the group above or Move to another group. Reorder round has gone.",
            "Average price per house: every customer's list price (two-price customers at the middle) ÷ customers, no extras. Its target is labelled Target.",
            "Customers includes those not started yet.",
            "Round: Move the rest to the next day ends today, moves today's bookings and offers to message them.",
            "Monthly Direct Debit: enter the monthly amount and the price per clean is worked out (a clean every 5 weeks).",
            "Change group: move a group next to one further away and keep it separate.",
            "Round review: skips only count against a house that's part of a group.",
            "The Undo bar shows for 5 seconds.",
            "Round: customers are due when the round reaches them, so someone missed last time waits with their neighbours instead of jumping to the front.",
            "Round: today's done customers fold into one \"Done today\" row (tap to show them), so the next customer is always at the top.",
            "Cleaned & paid for someone who already owes asks whether they paid the older cleans too.",
            "Averages only count finished days, so the first cleans of the morning don't skew them.",
            "Round: neighbours on the same street are kept on the same day (shown with a bar down the side). A cluster that won't fit starts the next day, and a later one that fits fills the gap. Change it per customer under Edit > Same day as the customer before.",
            "Front only... when logging: asks the amount each time, starting from last time's.",
            "Skipping someone who owes offers to send them a reminder by WhatsApp (wording in Settings).",
            "Round: swipe left on a later day's customer for Do today, to bring them into today's work.",
            "Once someone is skipped, today only tops back up to its real target, not target + 10%.",
            "More > Round review: houses that may be harming the round (cheap for the round, on their own, skipping a lot, slow to pay).",
            "Averages (per house, houses per workday, skip rate, round length) all use the last 12 months; totals stay exact.",
            "Customer pages show a small map (tap for directions). Map positions are found from the addresses in the background.",
            "Change group... on a customer's page (or press and hold on the Round list): join the group before or after, move to a group further away (nearest first), take a house out on its own, or merge whole groups.",
            "Average per house and Houses per workday charts: weekly bars with a 12-week average line.",
            "Charts all share one look: blue bars (orange for a week short of target), a dark trend line, dashed target or average.",
            "Round length is the average gap between cleans over the last 12 weeks (skips left out), updating as you log.",
            "Swiping Paid, Not paid or Skipped works like Mail: the row slides away and the list closes up.",
            "Round review never counts front-only houses as cheap, and its average leaves them out.",
            "Average per house and Houses per workday charts: the line is a rolling 12-week average.",
            "Faster logging: swipes and the log sheet finish their animation before the clean is saved, and the screens no longer re-read every customer's history after each save.",
        ]),
        Release(version: "1.1", date: "October 2026", changes: [
            "Round: the list carries on from where the day started, so cleaning someone out of order no longer moves anyone else.",
            "Round: customers done today stay in today's list, ticked and dimmed, and count towards the day. A skip frees their space.",
            "Round: messaging a day books those customers in, and they stay on that day.",
            "Round: every-other customers on their off round are shown greyed automatically.",
            "Round: each day shows £ done and £ left; swipe a row for Paid, Not paid or Skipped.",
            "Screens move on to the new day or week at midnight, even if the app was left open.",
            "Money Owed: search, and payments over what's owed are kept as credit for the next clean. An \"In credit\" list.",
            "Customers can have a second price (e.g. front only / full). Logging asks which, with the one not used last time first.",
            "Stats: \"Ideal\" figures for a target round length (Settings), from your houses per workday, customers and skip rate over the last 12 months. Tap one for the working, as planned and as actually worked.",
            "Stats: tap a card with › for its chart over time. Round length is now the measured gap between cleans; Price rises due no longer counts customers with no price date.",
            "Average per house is now worked out as the spreadsheet does it (the average of each day's £ per house).",
            "New customers: pick the round and area from a list, and they go after the last customer there unless placed by hand.",
            "Tap a visit in a customer's history to correct or delete it. More > History shows every visit by day.",
            "Delete a customer completely (for mistakes such as duplicates). A backup is saved first.",
        ]),
        Release(version: "1.0", date: "October 2026", changes: [
            "First version used side by side with the round spreadsheet.",
        ]),
    ]

    static var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static let seenVersionKey = "lastSeenAppVersion"

    /// Takes a backup the first time a new version opens, so there's a copy from just before any change it makes.
    @MainActor
    static func backupIfNewVersion(context: ModelContext, defaults: UserDefaults = .standard) {
        let current = currentVersion
        guard defaults.string(forKey: seenVersionKey) != current else { return }
        AutoBackup.runInBackground(context: context)
        defaults.set(current, forKey: seenVersionKey)
    }
}
