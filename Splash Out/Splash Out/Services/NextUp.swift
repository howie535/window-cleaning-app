import Foundation

/// Who's next on the round (Docs/SPEC.md section 4.6), following the workbook's Next Up sheet.
/// Pure logic on plain values, no storage, so it can be tested on its own.
enum NextUp {
    struct Candidate: Equatable {
        /// Caller's handle for the customer (e.g. an index).
        var key: Int
        /// Position in round order.
        var sequence: Int
        /// Active or leaving. Paused, not started and cancelled customers are never listed.
        var isListable: Bool
        var price: Decimal
        var everyOther: Bool
        var lastCleaned: Date?
        var lastNotDue: Date?
    }

    struct Day: Equatable {
        var date: Date
        /// The day's target in pounds (before any overbooking).
        var target: Decimal
    }

    struct Assignment: Equatable {
        var key: Int
        /// Index into the working days, or nil when they don't fit in the days available ("later").
        var dayIndex: Int?
        /// Running total of prices up to and including this customer.
        var cumulative: Decimal
    }

    /// The customer with the latest cleaned visit; on a tie, the one furthest along the round.
    static func pointer(in all: [Candidate]) -> Candidate? {
        all.filter { $0.lastCleaned != nil }.max { a, b in
            if a.lastCleaned! != b.lastCleaned! { return a.lastCleaned! < b.lastCleaned! }
            return a.sequence < b.sequence
        }
    }

    /// Whole days from `from` to `to` (both start-of-day).
    private static func days(from: Date, to: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// Hidden if cleaned too recently: 3 weeks normally, 8 for every-other customers
    /// (who are also hidden for 3 weeks after an off-cycle "not due").
    static func isDue(_ c: Candidate, today: Date, hideWeeks: Int, hideWeeksEveryOther: Int, calendar: Calendar) -> Bool {
        guard c.isListable else { return false }
        if let last = c.lastCleaned {
            let gapWeeks = c.everyOther ? hideWeeksEveryOther : hideWeeks
            if days(from: last, to: today, calendar: calendar) < 7 * gapWeeks { return false }
        }
        if c.everyOther, let notDue = c.lastNotDue, days(from: notDue, to: today, calendar: calendar) < 7 * hideWeeks {
            return false
        }
        return true
    }

    /// Customers in round order starting just after the pointer and wrapping, limited to those due.
    static func queue(
        _ all: [Candidate],
        today: Date,
        hideWeeks: Int,
        hideWeeksEveryOther: Int,
        calendar: Calendar
    ) -> [Candidate] {
        let ordered = all.sorted { $0.sequence < $1.sequence }
        let rotated: [Candidate]
        if let pointer = pointer(in: all) {
            rotated = ordered.filter { $0.sequence > pointer.sequence } + ordered.filter { $0.sequence <= pointer.sequence }
        } else {
            rotated = ordered
        }
        return rotated.filter { isDue($0, today: today, hideWeeks: hideWeeks, hideWeeksEveryOther: hideWeeksEveryOther, calendar: calendar) }
    }

    /// The next working days from `today`: those with a target above zero, within a look-ahead window.
    static func workingDays(
        from today: Date,
        maxDays: Int = 20,
        windowDays: Int = 49,
        calendar: Calendar,
        target: (Date) -> Decimal
    ) -> [Day] {
        var result: [Day] = []
        for offset in 0..<windowDays {
            guard result.count < maxDays, let date = calendar.date(byAdding: .day, value: offset, to: today) else { break }
            let dayTarget = target(date)
            if dayTarget > 0 { result.append(Day(date: date, target: dayTarget)) }
        }
        return result
    }

    /// Each customer goes on the first day whose cumulative booking capacity (target x (1 + overbook))
    /// covers the running total of prices. Spare capacity carries over rather than resetting daily.
    static func assign(_ queue: [Candidate], to days: [Day], overbook: Decimal) -> [Assignment] {
        var capacities: [Decimal] = []
        var running: Decimal = 0
        for day in days {
            running += day.target * (1 + overbook)
            capacities.append(running)
        }

        var total: Decimal = 0
        return queue.map { candidate in
            total += candidate.price
            let index = capacities.filter { $0 < total }.count
            return Assignment(key: candidate.key, dayIndex: index < days.count ? index : nil, cumulative: total)
        }
    }
}
