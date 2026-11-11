import Foundation
import SwiftData

/// Every visit grouped by customer, built from one fetch of all visits.
///
/// Why: after each save, SwiftData re-reads a customer's `visits` one customer at a time, which made every screen
/// rebuild slowly (~200 ms each) half a second after logging a clean. One fetch of all visits is ~35 ms.
/// A screen builds the index from its own `@Query` of visits at the start of its update, so it is never out of date.
struct VisitIndex {
    private var byCustomer: [PersistentIdentifier: [Visit]] = [:]

    /// What the Stats page needs: the last 13 months and this tax year (every card looks back 12 months at most),
    /// plus any clean not yet paid however old, so Money owed matches the Owed page. Keeps Stats quick as the
    /// history grows (it goes back to the 2025-6 worksheet). Applied to the screen's cached fetch of every visit:
    /// a filtered @Query fetches again on every redraw, which is slower.
    static func statsWindow(_ visits: [Visit], today: Date) -> [Visit] {
        let yearAgo = RoundCalendar.london.date(byAdding: .day, value: -400, to: today) ?? .distantPast
        let cutoff = min(yearAgo, TaxYear.range(startYear: TaxYear.startYear(containing: today)).lowerBound)
        return visits.filter { $0.date >= cutoff || $0.isUnpaid }
    }

    /// What the round needs: the last 12 months (the cycle length uses 120 days; the rest uses each customer's
    /// latest visits). Built once per launch for the round's @Query.
    nonisolated(unsafe) static let roundWindowAtLaunch: Predicate<Visit> = {
        let cutoff = RoundCalendar.london.date(byAdding: .day, value: -365, to: RoundCalendar.startOfDay()) ?? .distantPast
        return #Predicate<Visit> { $0.date >= cutoff }
    }()

    init(_ visits: [Visit]) {
        for visit in visits {
            if let id = visit.customer?.persistentModelID { byCustomer[id, default: []].append(visit) }
        }
    }

    func visits(for customer: Customer) -> [Visit] { byCustomer[customer.persistentModelID] ?? [] }
}

/// While a screen works out its figures, `Customer.allVisits` answers from that screen's index.
/// Used only synchronously inside a view update (begin ... end), so nothing outside sees it.
enum VisitLookup {
    nonisolated(unsafe) static var current: VisitIndex?

    @discardableResult
    static func begin(_ visits: [Visit]) -> Bool {
        current = VisitIndex(visits)
        return true
    }

    @discardableResult
    static func end() -> Bool {
        current = nil
        return true
    }

    /// Runs `work` with an index of every visit in `context` (one fetch), then puts back whatever index was in use.
    @MainActor
    static func with<T>(_ context: ModelContext, _ work: () throws -> T) rethrows -> T {
        let previous = current
        current = VisitIndex((try? context.fetch(FetchDescriptor<Visit>())) ?? [])
        defer { current = previous }
        return try work()
    }
}
