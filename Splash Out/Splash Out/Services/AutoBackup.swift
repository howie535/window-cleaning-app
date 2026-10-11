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

    // A folder the user chose in Files (iCloud Drive, OneDrive...). Each day's backup is copied there too.
    static let bookmarkKey = "autobackup.folderBookmark"
    static let folderNameKey = "autobackup.folderName"
    static let folderLastKey = "autobackup.folderLast"
    static let folderErrorKey = "autobackup.folderError"
    static let keepInFolder = 30

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
            copyToChosenFolder(url, defaults: defaults)
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

    // MARK: Chosen folder

    /// True when a folder is chosen and the last copy into it worked.
    static func folderWorks(defaults: UserDefaults = .standard) -> Bool {
        defaults.data(forKey: bookmarkKey) != nil && (defaults.string(forKey: folderErrorKey) ?? "").isEmpty
    }

    /// Remembers the folder the user picked (needs the access the picker gave, so call it right after picking).
    static func setFolder(_ url: URL, defaults: UserDefaults = .standard) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        defaults.set(try url.bookmarkData(), forKey: bookmarkKey)
        defaults.set(url.lastPathComponent, forKey: folderNameKey)
        defaults.set("", forKey: folderErrorKey)
    }

    static func clearFolder(defaults: UserDefaults = .standard) {
        for key in [bookmarkKey, folderNameKey, folderLastKey, folderErrorKey] { defaults.removeObject(forKey: key) }
    }

    /// Copies a finished daily backup into the chosen folder, and trims old copies there. A problem is noted for Settings
    /// to show; it never stops the app.
    static func copyToChosenFolder(_ file: URL, defaults: UserDefaults = .standard) {
        guard let bookmark = defaults.data(forKey: bookmarkKey) else { return }
        do {
            var stale = false
            let folder = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale)
            let accessing = folder.startAccessingSecurityScopedResource()
            defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
            if stale { defaults.set(try folder.bookmarkData(), forKey: bookmarkKey) }

            let destination = folder.appendingPathComponent(file.lastPathComponent)
            var coordinationError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { target in
                do { try Data(contentsOf: file).write(to: target) } catch { writeError = error }
            }
            if let failure = coordinationError ?? writeError.map({ $0 as NSError }) { throw failure }

            let old = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("splash-out-daily-") && $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for extra in old.dropLast(keepInFolder) { try? FileManager.default.removeItem(at: extra) }

            defaults.set(Date().timeIntervalSince1970, forKey: folderLastKey)
            defaults.set("", forKey: folderErrorKey)
        } catch {
            defaults.set("Couldn't save to the folder. Choose it again in Settings.", forKey: folderErrorKey)
        }
    }
}
