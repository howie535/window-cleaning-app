import CoreLocation

enum RouteOrdering {
    /// Greedy nearest-neighbor ordering. Customers without a known coordinate are left in their
    /// original relative order and appended after everything with a known location.
    static func order(_ customers: [Customer], startingFrom start: CLLocationCoordinate2D?) -> [Customer] {
        var located = customers.filter { $0.coordinate != nil }
        let unlocated = customers.filter { $0.coordinate == nil }

        guard !located.isEmpty else { return customers }

        var ordered: [Customer] = []
        var currentPoint = start

        while !located.isEmpty {
            let nextIndex: Int
            if let currentPoint {
                nextIndex = located.indices.min { lhs, rhs in
                    distance(from: currentPoint, to: located[lhs].coordinate!) <
                    distance(from: currentPoint, to: located[rhs].coordinate!)
                }!
            } else {
                nextIndex = 0
            }
            let next = located.remove(at: nextIndex)
            currentPoint = next.coordinate
            ordered.append(next)
        }

        return ordered + unlocated
    }

    private static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
}
