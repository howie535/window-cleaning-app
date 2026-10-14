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

    /// Works through customers with no position, one every couple of seconds (Apple limits how fast this can go).
    /// Addresses that couldn't be found are retried after two weeks.
    static func fillMissing(in context: ModelContext, defaults: UserDefaults = .standard) {
        // Not during the Simulator's self-test and import runs.
        guard running == nil, !CommandLine.arguments.contains("-ImportFile") else { return }
        running = Task { @MainActor in
            defer { running = nil }
            let customers = (try? context.fetch(FetchDescriptor<Customer>())) ?? []
            var failed = defaults.dictionary(forKey: failedKey) as? [String: Double] ?? [:]
            let twoWeeksAgo = Date().addingTimeInterval(-14 * 86_400).timeIntervalSince1970
            let todo = customers
                .filter { $0.coordinate == nil && $0.status != .cancelled && !$0.address.isEmpty }
                .filter { (failed[$0.id.uuidString] ?? 0) < twoWeeksAgo }
                .sorted { $0.sequence < $1.sequence }
            for customer in todo {
                if Task.isCancelled { break }
                if await find(customer) { failed[customer.id.uuidString] = nil } else { failed[customer.id.uuidString] = Date().timeIntervalSince1970 }
                defaults.set(failed, forKey: failedKey)
                try? context.save()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Stops looking things up (the app is going to the background).
    static func stop() {
        running?.cancel()
        running = nil
    }
}
