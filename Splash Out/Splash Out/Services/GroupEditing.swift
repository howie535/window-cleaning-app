import Foundation
import CoreLocation

/// Clusters on the round as lists of customers, and the changes the user can make to them: join the group before or
/// after, move into a group further away (moving round order), split out on their own, or merge whole groups.
@MainActor
enum GroupEditing {
    struct Cluster: Identifiable {
        let id: Int
        let members: [Customer]
        var name: String { RoundGrouping.streetName(members.first?.address ?? "") }
        var first: Customer { members[0] }
        var last: Customer { members[members.count - 1] }

        /// The middle of the cluster on the map, when its houses have been found.
        var centre: CLLocationCoordinate2D? {
            let points = members.compactMap(\.coordinate)
            guard !points.isEmpty else { return nil }
            return CLLocationCoordinate2D(latitude: points.map(\.latitude).reduce(0, +) / Double(points.count),
                                          longitude: points.map(\.longitude).reduce(0, +) / Double(points.count))
        }
    }

    /// Customers still on the round (not cancelled or paused), in round order.
    static func onRound(_ customers: [Customer]) -> [Customer] {
        customers.filter { $0.status != .cancelled && $0.status != .paused }.sorted { $0.sequence < $1.sequence }
    }

    /// Every cluster on the round, in round order.
    static func clusters(_ customers: [Customer]) -> [Cluster] {
        let ordered = onRound(customers)
        let numbers = RoundGrouping.groups(ordered.map { ($0.address, $0.groupWithPrevious) })
        var result: [Cluster] = []
        var current: [Customer] = []
        for index in ordered.indices {
            if index > 0 && numbers[index] != numbers[index - 1] {
                result.append(Cluster(id: result.count, members: current))
                current = []
            }
            current.append(ordered[index])
        }
        if !current.isEmpty { result.append(Cluster(id: result.count, members: current)) }
        return result
    }

    /// Other clusters, nearest first: the ones either side in the round, then by distance on the map where both are
    /// known, otherwise by how far away they are in the round.
    static func candidates(for cluster: Cluster, in all: [Cluster]) -> [Cluster] {
        let others = all.filter { $0.id != cluster.id }
        let adjacent = others.filter { abs($0.id - cluster.id) == 1 }.sorted { $0.id < $1.id }
        let rest = others.filter { abs($0.id - cluster.id) != 1 }.sorted { a, b in
            let da = distance(cluster, a), db = distance(cluster, b)
            switch (da, db) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return abs(a.id - cluster.id) < abs(b.id - cluster.id)
            }
        }
        return adjacent + rest
    }

    /// Metres between two clusters' centres, if both are on the map.
    static func distance(_ a: Cluster, _ b: Cluster) -> Double? {
        guard let ca = a.centre, let cb = b.centre else { return nil }
        return CLLocation(latitude: ca.latitude, longitude: ca.longitude).distance(from: CLLocation(latitude: cb.latitude, longitude: cb.longitude))
    }

    /// Moves `movers` (in their current order) or the whole of `source` into `target`. Next to each other in the
    /// round, nobody moves; further away, the movers go after the target's last house.
    /// With `joining` false (only for a group further away), the movers sit straight after the target but stay their own group.
    static func join(_ movers: [Customer], into target: Cluster, all customers: [Customer], joining: Bool = true) {
        let ordered = onRound(customers)
        guard let firstMover = movers.first, let lastMover = movers.last else { return }
        let firstIndex = ordered.firstIndex { $0 === firstMover } ?? 0
        let lastIndex = ordered.firstIndex { $0 === lastMover } ?? 0
        let targetFirst = ordered.firstIndex { $0 === target.first } ?? 0
        let targetLast = ordered.firstIndex { $0 === target.last } ?? 0

        if targetLast + 1 == firstIndex {
            // The group just before: the movers join it, and whoever followed them stays apart.
            firstMover.groupWithPrevious = true
            for m in movers.dropFirst() { m.groupWithPrevious = true }
            if lastIndex + 1 < ordered.count, !movers.contains(where: { $0 === ordered[lastIndex + 1] }) {
                ordered[lastIndex + 1].groupWithPrevious = false
            }
        } else if lastIndex + 1 == targetFirst {
            // The group just after: the movers lead it, apart from whoever was before them.
            firstMover.groupWithPrevious = false
            for m in movers.dropFirst() { m.groupWithPrevious = true }
            target.first.groupWithPrevious = true
        } else {
            // Further away: move them in the round to just after the target group.
            let after = targetLast + 1 < ordered.count ? ordered[targetLast + 1] : nil
            let afterWasInTarget = after.map { a in target.members.contains { $0 === a } } ?? false
            let followerOfMovers = lastIndex + 1 < ordered.count ? ordered[lastIndex + 1] : nil
            var everyone = customers.sorted { $0.sequence < $1.sequence }
            everyone.removeAll { c in movers.contains { $0 === c } }
            let insertAt = (everyone.firstIndex { $0 === target.last } ?? (everyone.count - 1)) + 1
            everyone.insert(contentsOf: movers, at: insertAt)
            for (index, customer) in everyone.enumerated() where customer.sequence != index + 1 { customer.sequence = index + 1 }
            firstMover.groupWithPrevious = joining
            for m in movers.dropFirst() { m.groupWithPrevious = true }
            for m in movers where m.round != target.last.round { m.round = target.last.round }
            if let after, !afterWasInTarget, !movers.contains(where: { $0 === after }) { after.groupWithPrevious = false }
            // Whoever followed the movers' old place no longer joins on to them.
            if let follower = followerOfMovers, !movers.contains(where: { $0 === follower }), follower.groupWithPrevious == true {
                follower.groupWithPrevious = nil
            }
        }
    }

    /// Takes a customer out of their group so they're a group of one.
    static func standAlone(_ customer: Customer, all customers: [Customer]) {
        let ordered = onRound(customers)
        customer.groupWithPrevious = false
        if let index = ordered.firstIndex(where: { $0 === customer }), index + 1 < ordered.count {
            let next = ordered[index + 1]
            let cluster = clusters(customers).first { $0.members.contains { $0 === customer } }
            if cluster?.members.contains(where: { $0 === next }) == true { next.groupWithPrevious = false }
        }
    }

    // MARK: Dragging on the Customers page

    /// Moves `mover` to just after `target` in the round and into `target`'s group. Everyone else keeps their group.
    static func move(_ mover: Customer, after target: Customer, all customers: [Customer]) {
        guard mover !== target else { return }
        var groups = groupNumbers(customers)
        groups[ObjectIdentifier(mover)] = groups[ObjectIdentifier(target)]
        var everyone = customers.sorted { $0.sequence < $1.sequence }
        everyone.removeAll { $0 === mover }
        everyone.insert(mover, at: (everyone.firstIndex { $0 === target } ?? (everyone.count - 1)) + 1)
        renumber(everyone)
        if mover.round != target.round { mover.round = target.round }
        settle(groups, all: customers)
    }

    /// Moves `mover` to the front of `cluster` (dropped on the group's heading).
    static func move(_ mover: Customer, toStartOf cluster: Cluster, all customers: [Customer]) {
        guard cluster.first !== mover else { return }
        var groups = groupNumbers(customers)
        groups[ObjectIdentifier(mover)] = groups[ObjectIdentifier(cluster.first)]
        var everyone = customers.sorted { $0.sequence < $1.sequence }
        everyone.removeAll { $0 === mover }
        everyone.insert(mover, at: everyone.firstIndex { $0 === cluster.first } ?? 0)
        renumber(everyone)
        if mover.round != cluster.first.round { mover.round = cluster.first.round }
        settle(groups, all: customers)
    }

    /// Ends the group after `customer`: whoever follows them starts a new group.
    static func newGroup(after customer: Customer, all customers: [Customer]) {
        let ordered = onRound(customers)
        guard let index = ordered.firstIndex(where: { $0 === customer }), index + 1 < ordered.count else { return }
        var groups = groupNumbers(customers)
        let next = 1_000_000
        for c in ordered[(index + 1)...] where groups[ObjectIdentifier(c)] == groups[ObjectIdentifier(customer)] {
            groups[ObjectIdentifier(c)] = next
        }
        settle(groups, all: customers)
    }

    /// Joins `customer` (the first of their group) and the rest of their group on to the group above.
    static func joinGroupAbove(_ customer: Customer, all customers: [Customer]) {
        let ordered = onRound(customers)
        guard let index = ordered.firstIndex(where: { $0 === customer }), index > 0 else { return }
        var groups = groupNumbers(customers)
        let mine = groups[ObjectIdentifier(customer)], above = groups[ObjectIdentifier(ordered[index - 1])]
        for c in ordered where groups[ObjectIdentifier(c)] == mine { groups[ObjectIdentifier(c)] = above }
        settle(groups, all: customers)
    }

    /// Each on-round customer's group number as things stand.
    private static func groupNumbers(_ customers: [Customer]) -> [ObjectIdentifier: Int] {
        var result: [ObjectIdentifier: Int] = [:]
        for cluster in clusters(customers) { for c in cluster.members { result[ObjectIdentifier(c)] = cluster.id } }
        return result
    }

    private static func renumber(_ ordered: [Customer]) {
        for (index, customer) in ordered.enumerated() where customer.sequence != index + 1 { customer.sequence = index + 1 }
    }

    /// Sets "same day as the customer before" wherever it's needed so the groups come out as `groups` says, leaving
    /// the automatic (same street) setting alone where it already gives the right answer.
    private static func settle(_ groups: [ObjectIdentifier: Int], all customers: [Customer]) {
        let ordered = onRound(customers)
        for (index, c) in ordered.enumerated() where index > 0 {
            let previous = ordered[index - 1]
            let want = groups[ObjectIdentifier(c)] != nil && groups[ObjectIdentifier(c)] == groups[ObjectIdentifier(previous)]
            let automatic = RoundGrouping.sameStreet(previous.address, c.address)
            let now = c.groupWithPrevious ?? automatic
            if now != want { c.groupWithPrevious = want == automatic ? nil : want }
        }
    }
}
