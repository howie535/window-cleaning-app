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
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // Deliberately not wiping the store on failure: it will hold the real round.
            fatalError("Couldn't open the data store: \(error)")
        }
    }

    /// Makes sure the single settings row exists. A fresh install holds no crews or names: the user adds their own.
    static func seedDefaultsIfNeeded(in context: ModelContext) {
        if (try? context.fetchCount(FetchDescriptor<AppSettings>())) == 0 {
            context.insert(AppSettings())
        }
    }
}
