import Foundation
import SwiftData

/// A daily safety copy of everything, saved on the device in Files > On My iPhone > Splash Out > Backups > Daily.
/// Each file is the same format as "Export backup", so it can be put back with Settings > Import round data.
/// One file per day (rewritten as the day goes on), the newest 14 kept. Never written when the app holds no customers,
/// so an empty or freshly wiped app can't replace a good copy.
@MainActor
enum AutoBackup {
    static let lastKey = "autobackup.last"
    static let exportedKey = "export.last"
    static let keepDays = 14

    nonisolated static var directory: URL {
        ExportService.backupDirectory.appendingPathComponent("Daily", isDirectory: true)
    }

    @discardableResult
    static func run(context: ModelContext, directory: URL = AutoBackup.directory, now: Date = Date(), defaults: UserDefaults = .standard) -> URL? {
        guard ((try? context.fetchCount(FetchDescriptor<Customer>())) ?? 0) > 0 else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("splash-out-daily-\(RoundCalendar.dayString(now)).json")
            try ExportService.data(from: context).write(to: url, options: .atomic)
            defaults.set(now.timeIntervalSince1970, forKey: lastKey)
            prune(directory: directory)
            return url
        } catch {
            return nil   // a failed backup must never get in the way of using the app
        }
    }

    /// At most about every 6 hours unless forced (used when the app opens; it also runs when the app goes to the background).
    static func runIfDue(context: ModelContext, defaults: UserDefaults = .standard) {
        let last = defaults.double(forKey: lastKey)
        if Date().timeIntervalSince1970 - last > 6 * 3600 { run(context: context) }
    }

    private static func prune(directory: URL) {
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("splash-out-daily-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for old in files.dropLast(keepDays) { try? FileManager.default.removeItem(at: old) }
    }
}
