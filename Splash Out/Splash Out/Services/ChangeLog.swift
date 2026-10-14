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
            "Round: customers are due when the round reaches them, so someone missed last time waits with their neighbours instead of jumping to the front.",
            "Round: today's done customers fold into one \"Done today\" row (tap to show them), so the next customer is always at the top.",
            "Cleaned & paid for someone who already owes asks whether they paid the older cleans too.",
            "Averages only count finished days, so the first cleans of the morning don't skew them.",
            "Smoother, clearer charts.",
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
        AutoBackup.run(context: context)
        defaults.set(current, forKey: seenVersionKey)
    }
}
