import Foundation

/// Who's next on the round (Docs/SPEC.md section 4.6).
/// Pure logic on plain values, no storage, so it can be tested on its own.
///
/// How the list is built:
/// - A customer is **done this lap** if they had any visit (clean, skip or not due) in the last `hideWeeks` weeks.
/// - The list carries on from where the round had got to **at the start of today** (the last customer visited before
///   today; on a tie, the one furthest along). Nothing done today changes the order, so cleaning someone further
///   down never pushes the customers above them to the end, and anyone passed over earlier stays near the top.
/// - Customers visited **today** stay on today, shown as done; a clean counts towards today's total, so marking a
///   clean never pulls new customers onto the day. A skip doesn't count, so the next customers move up.
/// - **Booked** customers (messaged for a day) stay on that day whatever else happens.
/// - **Every-other** customers who were cleaned last lap are shown greyed as "not this round" and aren't counted.
/// - Each day is then filled in round order until it reaches its target plus the overbook allowance.
enum NextUp {
    struct Candidate: Equatable {
        /// Caller's handle for the customer (e.g. an index).
        var key: Int
        /// Position in round order.
        var sequence: Int
        /// Active or leaving. Paused, not started and cancelled customers are never booked.
        var isListable: Bool
        var price: Decimal
        var everyOther: Bool
        var lastCleaned: Date?
        var lastNotDue: Date?
        /// The latest visit of any kind (cleaned, skipped or not due).
        var lastVisit: Date?
        /// The latest visit before today: where the round had got to when the day started.
        var lastVisitBeforeToday: Date? = nil
        /// Not started yet: shown in the round, greyed, but never counted in a day's total.
        var isPending: Bool = false
        /// What happened today, if they've been visited today.
        var visitedToday: VisitKind? = nil
        /// What was charged for today's clean (counts towards today's total).
        var chargedToday: Decimal = 0
        /// The day they've been booked in for (messaged), if any.
        var bookedFor: Date? = nil
    }

    struct Day: Equatable {
        var date: Date
        /// The day's target in pounds (before any overbooking).
        var target: Decimal
    }

    enum State: Equatable {
        /// Planned for the day (counts towards its total).
        case planned
        /// Booked for this day by message (counts towards its total).
        case booked
        /// Visited today.
        case cleanedToday
        case skippedToday
        case notDueToday
        /// Not started yet (greyed, not counted).
        case notStarted
        /// Every-other customer on their off round (greyed, not counted).
        case everyOtherOff

        var counts: Bool { self == .planned || self == .booked }
    }

    struct Placement: Equatable {
        var key: Int
        /// Index into the working days, or nil when they don't fit in the days available ("later").
        var dayIndex: Int?
        var state: State
        /// Position in the lap (round order from the lap start), for sorting rows within a day.
        var order: Int
    }

    // MARK: Helpers

    /// Whole days from `from` to `to` (both start-of-day). Rounding the hours copes with the 23- and 25-hour days
    /// when the clocks change, and is far quicker than asking the calendar, which matters with thousands of visits.
    private static func days(from: Date, to: Date, calendar: Calendar) -> Int {
        Int((to.timeIntervalSince(from) / 86_400).rounded())
    }

    /// The customer most recently dealt with (latest visit; on a tie, the one furthest along the round).
    /// Only used to say where the round is "carrying on from".
    static func pointer(in all: [Candidate]) -> Candidate? {
        func date(_ c: Candidate) -> Date? { c.lastVisit ?? c.lastCleaned }
        return all.filter { date($0) != nil }.max { a, b in
            if date(a)! != date(b)! { return date(a)! < date(b)! }
            return a.sequence < b.sequence
        }
    }

    static func isDoneThisLap(_ c: Candidate, today: Date, hideWeeks: Int, calendar: Calendar) -> Bool {
        guard let last = c.lastVisit else { return false }
        return days(from: last, to: today, calendar: calendar) < 7 * hideWeeks
    }

    /// An every-other customer cleaned within about one and a half laps is on their off round.
    static func isEveryOtherOff(_ c: Candidate, today: Date, lapDays: Int, factor: Double, calendar: Calendar) -> Bool {
        guard c.everyOther, let cleaned = c.lastCleaned else { return false }
        return Double(days(from: cleaned, to: today, calendar: calendar)) < Double(lapDays) * factor
    }

    /// Due today: not done this lap (and not on an every-other off round).
    static func isDue(_ c: Candidate, today: Date, hideWeeks: Int, lapDays: Int = 35, everyOtherFactor: Double = 1.5, calendar: Calendar) -> Bool {
        c.isListable
            && !isDoneThisLap(c, today: today, hideWeeks: hideWeeks, calendar: calendar)
            && !isEveryOtherOff(c, today: today, lapDays: lapDays, factor: everyOtherFactor, calendar: calendar)
    }

    /// Where the round had got to at the start of today: the last customer visited before today
    /// (on a tie, the one furthest along the round).
    static func startOfDayPointer(in all: [Candidate]) -> Candidate? {
        all.filter { $0.lastVisitBeforeToday != nil }.max { a, b in
            if a.lastVisitBeforeToday! != b.lastVisitBeforeToday! { return a.lastVisitBeforeToday! < b.lastVisitBeforeToday! }
            return a.sequence < b.sequence
        }
    }

    /// Everyone in round order, carrying on just after where the round had got to at the start of today.
    static func lapOrder(_ all: [Candidate], today: Date, hideWeeks: Int, calendar: Calendar) -> [Candidate] {
        let ordered = all.sorted { $0.sequence < $1.sequence }
        guard let pointer = startOfDayPointer(in: all) else { return ordered }
        return ordered.filter { $0.sequence > pointer.sequence } + ordered.filter { $0.sequence <= pointer.sequence }
    }

    /// The next working days from `today`: those with a target above zero, within a look-ahead window.
    static func workingDays(
        from today: Date,
        maxDays: Int = 40,
        windowDays: Int = 150,
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

    // MARK: Plan

    static func plan(
        _ all: [Candidate],
        days: [Day],
        today: Date,
        overbook: Decimal,
        hideWeeks: Int,
        lapDays: Int,
        everyOtherFactor: Double = 1.5,
        calendar: Calendar
    ) -> [Placement] {
        let lap = lapOrder(all, today: today, hideWeeks: hideWeeks, calendar: calendar)
        let capacity = days.map { $0.target * (1 + overbook) }
        var load = [Decimal](repeating: 0, count: days.count)
        let todayIndex = days.firstIndex { $0.date == today }
        var placed = Set<Int>()
        var result: [Placement] = []

        // 1. Visited today: stay on today. A clean counts; a skip or not-due doesn't.
        for (order, c) in lap.enumerated() {
            guard let kind = c.visitedToday, let todayIndex else { continue }
            let state: State = switch kind {
            case .cleaned: .cleanedToday
            case .skipped: .skippedToday
            case .notDue: .notDueToday
            }
            if state == .cleanedToday { load[todayIndex] += c.chargedToday }
            result.append(Placement(key: c.key, dayIndex: todayIndex, state: state, order: order))
            placed.insert(c.key)
        }

        // 2. Booked: on their booked day.
        for (order, c) in lap.enumerated() where !placed.contains(c.key) && c.isListable {
            guard let booked = c.bookedFor, booked >= today, let index = days.firstIndex(where: { $0.date == booked }) else { continue }
            load[index] += c.price
            result.append(Placement(key: c.key, dayIndex: index, state: .booked, order: order))
            placed.insert(c.key)
        }

        // 3. Everyone else due, in lap order, filling each day to its target plus overbook.
        var day = 0
        func skipFullDays() { while day < days.count && load[day] >= capacity[day] { day += 1 } }
        skipFullDays()
        for (order, c) in lap.enumerated() where !placed.contains(c.key) {
            if c.isPending {
                if day < days.count { result.append(Placement(key: c.key, dayIndex: day, state: .notStarted, order: order)) }
                continue
            }
            guard c.isListable, !isDoneThisLap(c, today: today, hideWeeks: hideWeeks, calendar: calendar) else { continue }
            if isEveryOtherOff(c, today: today, lapDays: lapDays, factor: everyOtherFactor, calendar: calendar) {
                if day < days.count { result.append(Placement(key: c.key, dayIndex: day, state: .everyOtherOff, order: order)) }
                continue
            }
            guard day < days.count else {
                result.append(Placement(key: c.key, dayIndex: nil, state: .planned, order: order))
                continue
            }
            load[day] += c.price
            result.append(Placement(key: c.key, dayIndex: day, state: .planned, order: order))
            if load[day] >= capacity[day] { day += 1; skipFullDays() }
        }
        return result
    }

    /// Typical days between cleans: the median gap between consecutive cleans of regular (not every-other) customers,
    /// using cleans in the last `recentDays`. Falls back to `fallback` with too little history.
    static func lapDays(cleanDates: [[Date]], today: Date, recentDays: Int = 120, fallback: Int, calendar: Calendar) -> Int {
        var gaps: [Int] = []
        for dates in cleanDates {
            let sorted = dates.sorted()
            for (a, b) in zip(sorted, sorted.dropFirst()) where days(from: b, to: today, calendar: calendar) <= recentDays {
                let gap = days(from: a, to: b, calendar: calendar)
                if gap >= 14 { gaps.append(gap) }   // ignore re-cleans and corrections
            }
        }
        guard gaps.count >= 20 else { return fallback }
        gaps.sort()
        return min(max(gaps[gaps.count / 2], 21), 90)
    }
}
