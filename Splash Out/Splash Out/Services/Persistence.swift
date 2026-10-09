import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([
        Customer.self, Visit.self, PriceChange.self, Crew.self, WorkDay.self, Tip.self, AppSettings.self,
    ])

    /// Local-only for now. Once the iCloud capability and container exist (paid developer account),
    /// change `.none` to `.private("iCloud.com.splashout.Splash-Out")`.
    /// When that happens, make sure the default settings row is only seeded once, or two
    /// devices will each create their own copy.
    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        snapshotStoreIfNeeded(at: configuration.url)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // Deliberately not wiping the store on failure: it will hold the real round.
            fatalError("Couldn't open the data store: \(error)")
        }
    }

    /// Before the database is opened: copies the raw store files into Documents/Backups/Store snapshots when the app
    /// version has changed since last time, or when the last snapshot is over a week old. If an update ever changed the
    /// database in a way that can't be converted automatically, the data from just before it is still on the phone.
    /// Only the newest four are kept. Skipped when there is no database yet (a fresh install).
    static func snapshotStoreIfNeeded(at storeURL: URL, defaults: UserDefaults = .standard, now: Date = Date()) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else { return }

        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "0")(\(info?["CFBundleVersion"] as? String ?? "0"))"
        let lastVersion = defaults.string(forKey: "snapshot.lastVersion")
        let lastDate = defaults.object(forKey: "snapshot.lastDate") as? Date
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        guard lastVersion != version || (lastDate ?? .distantPast) < weekAgo else { return }

        let root = ExportService.backupDirectory.appendingPathComponent("Store snapshots", isDirectory: true)
        let folder = root.appendingPathComponent("\(RoundCalendar.fileStamp(now)) before \(version)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: storeURL.path + suffix)
                if fileManager.fileExists(atPath: source.path) {
                    try fileManager.copyItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
                }
            }
            defaults.set(version, forKey: "snapshot.lastVersion")
            defaults.set(now, forKey: "snapshot.lastDate")

            let existing = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.hasDirectoryPath }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for old in existing.dropLast(4) { try? fileManager.removeItem(at: old) }
        } catch {
            // A failed snapshot must never stop the app opening.
            try? fileManager.removeItem(at: folder)
        }
    }

    /// Makes sure the single settings row exists. A fresh install holds no crews or names: the user adds their own.
    static func seedDefaultsIfNeeded(in context: ModelContext) {
        if (try? context.fetchCount(FetchDescriptor<AppSettings>())) == 0 {
            context.insert(AppSettings())
        }
        // One-off: the round rule changed from "hide for 3 weeks" to "due again after 5 weeks".
        if !UserDefaults.standard.bool(forKey: "migration.dueAfter5Weeks") {
            if let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first, settings.nextUpHideWeeks == 3 {
                settings.nextUpHideWeeks = 5
            }
            UserDefaults.standard.set(true, forKey: "migration.dueAfter5Weeks")
        }
    }
}
