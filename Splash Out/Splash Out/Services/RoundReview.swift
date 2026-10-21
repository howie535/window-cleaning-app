import Foundation

/// Houses that may be harming the round: cheap for the round and on their own count most; skipping a lot (only when
/// part of a group) and being slow to pay count less. Each reason adds points; houses on 3 or more are listed (Docs: day-three notes).
enum RoundReview {
    struct Row: Identifiable {
        let customer: Customer
        let score: Double
        let reasons: [String]
        /// Front only: never counted as cheap (it's a smaller job).
        let frontOnly: Bool
        var id: UUID { customer.id }
    }

    /// Points for being cheap: 0 until 10% under the average, then 1 for every 10% under (at most 4).
    static func cheapPoints(price: Decimal, average: Decimal) -> Double {
        guard average > 0 else { return 0 }
        let under = NSDecimalNumber(decimal: (average - price) / average).doubleValue
        return under < 0.1 ? 0 : min(4, (under * 10).rounded(.down))
    }

    /// Marked front only, or their last three cleans were all logged as front only.
    @MainActor
    static func isFrontOnly(_ customer: Customer) -> Bool {
        if customer.frontOnly { return true }
        let recent = customer.allVisits.filter { $0.kind == .cleaned }.sorted { $0.date > $1.date }.prefix(3)
        return recent.count == 3 && recent.allSatisfy { $0.note == VisitLogger.frontOnlyNote }
    }

    /// Every customer on the round with their points and reasons, highest first.
    @MainActor
    static func rows(customers: [Customer], today: Date, threshold: Double = 3) -> (rows: [Row], average: Decimal) {
        let onRound = RoundMetrics.onRound(customers).filter { $0.price > 0 }
        let frontOnly = Set(onRound.filter(isFrontOnly).map(\.id))
        // The average is of full cleans only, so front-only prices don't drag it down.
        let full = onRound.filter { !frontOnly.contains($0.id) }
        let weights = full.map { $0.everyOther ? Decimal(0.5) : Decimal(1) }
        let totalWeight = weights.reduce(0, +)
        let average = totalWeight > 0 ? zip(full, weights).reduce(Decimal(0)) { $0 + $1.0.price * $1.1 } / totalWeight : 0

        // Clusters over everyone still on the round, in round order (as the planner does).
        let ordered = customers.filter { $0.status != .cancelled && $0.status != .paused }.sorted { $0.sequence < $1.sequence }
        let groups = RoundGrouping.groups(ordered.map { ($0.address, $0.groupWithPrevious) })
        var groupSize: [Int: Int] = [:]
        for g in groups { groupSize[g, default: 0] += 1 }
        var alone: Set<UUID> = []
        for (customer, g) in zip(ordered, groups) where groupSize[g] == 1 { alone.insert(customer.id) }

        let yearAgo = RoundCalendar.london.date(byAdding: .day, value: -365, to: today)!
        var result: [Row] = []
        for customer in onRound {
            var score = 0.0
            var reasons: [String] = []
            let isFront = frontOnly.contains(customer.id)
            let cheap = isFront ? 0 : cheapPoints(price: customer.price, average: average)
            if cheap > 0 {
                score += cheap
                let under = Int((NSDecimalNumber(decimal: (average - customer.price) / average).doubleValue * 100).rounded())
                reasons.append("\(under)% under average")
            }
            if alone.contains(customer.id) {
                score += 2
                reasons.append("On its own")
            }
            let recent = customer.allVisits.filter { $0.kind != .notDue && $0.date >= yearAgo && $0.date < today }
            let skips = recent.filter { $0.kind == .skipped }.count
            // A skip only hurts when the house is part of a group (the crew is there anyway and has to go back);
            // a house on its own that skips just isn't visited.
            if !alone.contains(customer.id) && skips >= 2 && Double(skips) / Double(max(1, recent.count)) >= 0.25 {
                score += 1
                reasons.append("Skips in a group: \(skips) of \(recent.count)")
            }
            let owed = customer.allVisits.filter(\.isUnpaid)
            let oldest = owed.map(\.date).min()
            let longOwed = oldest.map { (RoundCalendar.london.dateComponents([.day], from: $0, to: today).day ?? 0) > 42 } ?? false
            if owed.count >= 2 || longOwed {
                score += 1
                reasons.append(owed.count >= 2 ? "Owes for \(owed.count) cleans" : "Owed over 6 weeks")
            }
            if score >= threshold { result.append(Row(customer: customer, score: score, reasons: reasons, frontOnly: isFront)) }
        }
        result.sort { $0.score != $1.score ? $0.score > $1.score : $0.customer.price < $1.customer.price }
        return (result, average)
    }
}
