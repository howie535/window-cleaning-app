import Foundation
import SwiftData
import CoreLocation

/// Finds each customer's spot on the map from their address (Apple Maps), a few at a time while the app is open,
/// and keeps it. Used for the map on the customer page and for "nearest group".
@MainActor
enum MapPositions {
    private static var running: Task<Void, Never>?
    private static let failedKey = "mapPositions.failed"

    /// The address as Apple Maps should read it: with the area and country, so "27 Bron Wern" finds Llanddulas.
    static func query(for customer: Customer) -> String {
        [customer.address, customer.area, "UK"].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: ", ")
    }

    /// Looks one customer up now (when their page opens). Returns true if a position was found.
    @discardableResult
    static func find(_ customer: Customer) async -> Bool {
        guard !customer.address.trimmingCharacters(in: .whitespaces).isEmpty,
              let coordinate = await Geocoding.coordinate(for: query(for: customer)) else { return false }
        customer.latitude = coordinate.latitude
        customer.longitude = coordinate.longitude
        return true
    }

    /// Positions found but not yet saved. Saving each one as it came made every screen rebuild every couple of
    /// seconds (a hitch at the end of scrolling), so they're saved together instead.
    private static var found: [PersistentIdentifier: CLLocationCoordinate2D] = [:]
    private static weak var foundContext: ModelContext?

    /// Works through customers with no position, one every couple of seconds (Apple limits how fast this can go),
    /// saving them all together every 100, at the end, or when the app goes to the background.
    /// Addresses that couldn't be found are retried after two weeks.
    static func fillMissing(in context: ModelContext, defaults: UserDefaults = .standard) {
        // Not during the Simulator's self-test and import runs.
        guard running == nil, !CommandLine.arguments.contains("-ImportFile") else { return }
        foundContext = context
        running = Task { @MainActor in
            defer { running = nil }
            let customers = (try? context.fetch(FetchDescriptor<Customer>())) ?? []
            var failed = defaults.dictionary(forKey: failedKey) as? [String: Double] ?? [:]
            let twoWeeksAgo = Date().addingTimeInterval(-14 * 86_400).timeIntervalSince1970
            let todo = customers
                .filter { $0.coordinate == nil && $0.status != .cancelled && !$0.address.isEmpty }
                .filter { (failed[$0.id.uuidString] ?? 0) < twoWeeksAgo }
                .sorted { $0.sequence < $1.sequence }
                .map { (id: $0.persistentModelID, key: $0.id.uuidString, query: query(for: $0)) }
            for item in todo {
                if Task.isCancelled { break }
                if let coordinate = await Geocoding.coordinate(for: item.query) {
                    found[item.id] = coordinate
                    failed[item.key] = nil
                } else {
                    failed[item.key] = Date().timeIntervalSince1970
                }
                // Saved with the positions, not every lookup: each settings write made the Round screen refresh.
                if found.count >= 100 { saveFound(); defaults.set(failed, forKey: failedKey) }
                try? await Task.sleep(for: .seconds(2))
            }
            saveFound()
            defaults.set(failed, forKey: failedKey)
        }
    }

    /// Writes the positions found so far, in one save.
    static func saveFound() {
        guard !found.isEmpty, let context = foundContext else { return }
        for (id, coordinate) in found {
            guard let customer = context.model(for: id) as? Customer, customer.coordinate == nil else { continue }
            customer.latitude = coordinate.latitude
            customer.longitude = coordinate.longitude
        }
        found = [:]
        try? context.save()
    }

    /// Stops looking things up (the app is going to the background) and saves what was found.
    static func stop() {
        running?.cancel()
        running = nil
        saveFound()
    }
}
