import Foundation
import SwiftData

/// Every visit grouped by customer, built from one fetch of all visits.
///
/// Why: after each save, SwiftData re-reads a customer's `visits` one customer at a time, which made every screen
/// rebuild slowly (~200 ms each) half a second after logging a clean. One fetch of all visits is ~35 ms.
/// A screen builds the index from its own `@Query` of visits at the start of its update, so it is never out of date.
struct VisitIndex {
    private var byCustomer: [PersistentIdentifier: [Visit]] = [:]

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
}
