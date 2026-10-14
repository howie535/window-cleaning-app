import Foundation

/// Who's next on the round (Docs/SPEC.md section 4.6).
/// Pure logic on plain values, no storage, so it can be tested on its own.
///
/// How the list is built:
/// - A customer is **done this lap** if they had any visit (clean, skip or not due) in the `hideWeeks` weeks before the day
///   the round reaches them ("due when it's their turn").
/// - The list carries on from where the round had got to **at the start of today** (the last customer visited before
///   today; on a tie, the one furthest along). Nothing done today changes the order, so cleaning someone further
///   down never pushes the customers above them to the end, and anyone passed over earlier stays near the top.
/// - Customers visited **today** stay on today, shown as done; a clean counts towards today's total, so marking a
///   clean never pulls new customers onto the day. A skip doesn't count, so the next customers move up.
/// - **Booked** customers (messaged for a day) stay on that day whatever else happens.
/// - **Every-other** customers who were cleaned last lap are shown greyed as "not this round" and aren't counted.
/// - Each day is then filled in round order, a whole cluster of neighbours at a time, until it reaches its target plus
///   the overbook allowance. A cluster that won't fit starts the next day and a later one that fits fills the gap.
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
        /// Their cluster (neighbours kept on the same day). nil: a cluster of their own.
        var group: Int? = nil
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

        // 3. Everyone else, in lap order, a whole cluster at a time, filling each day to its target plus overbook.
        //    A cluster that won't fit in the space left starts the next day, and a later cluster that does fit (looking a
        //    few ahead) fills the gap. A cluster bigger than a whole day is split.
        //    Due "when it's their turn": measured from the day the round reaches them, not from today, so a customer
        //    missed last time waits for their neighbours instead of jumping to the front.
        struct Member { var order: Int; var c: Candidate }
        var units: [[Member]] = []
        func groupID(_ c: Candidate) -> Int { c.group ?? -1 - c.key }
        for (order, c) in lap.enumerated() where !placed.contains(c.key) {
            if let last = units.last?.last, groupID(last.c) == groupID(c) {
                units[units.count - 1].append(Member(order: order, c: c))
            } else {
                units.append([Member(order: order, c: c)])
            }
        }

        enum Role { case counts, notStarted, everyOtherOff, skip }
        func turn(_ day: Int) -> Date {
            day < days.count ? days[day].date : (days.last.map { calendar.date(byAdding: .day, value: 1, to: $0.date)! } ?? today)
        }
        func role(_ c: Candidate, _ day: Int) -> Role {
            if c.isPending { return .notStarted }
            let date = turn(day)
            guard c.isListable, !isDoneThisLap(c, today: date, hideWeeks: hideWeeks, calendar: calendar) else { return .skip }
            if isEveryOtherOff(c, today: date, lapDays: lapDays, factor: everyOtherFactor, calendar: calendar) { return .everyOtherOff }
            return .counts
        }
        func need(_ unit: [Member], _ day: Int) -> Decimal {
            unit.filter { role($0.c, day) == .counts }.reduce(0) { $0 + $1.c.price }
        }
        func place(_ unit: [Member], _ day: Int?) {
            for m in unit {
                switch role(m.c, day ?? days.count) {
                case .skip: continue
                case .notStarted: if let day { result.append(Placement(key: m.c.key, dayIndex: day, state: .notStarted, order: m.order)) }
                case .everyOtherOff: if let day { result.append(Placement(key: m.c.key, dayIndex: day, state: .everyOtherOff, order: m.order)) }
                case .counts:
                    if let day { load[day] += m.c.price }
                    result.append(Placement(key: m.c.key, dayIndex: day, state: .planned, order: m.order))
                }
            }
        }

        var day = 0
        func skipFullDays() { while day < days.count && load[day] >= capacity[day] { day += 1 } }
        skipFullDays()
        var queue = units
        /// Puts the front cluster on today up to capacity; the rest of it goes first tomorrow.
        func splitFront() {
            var rest: [Member] = []
            for m in queue[0] {
                if !rest.isEmpty || load[day] >= capacity[day] { rest.append(m); continue }
                place([m], day)
            }
            if rest.isEmpty { queue.removeFirst() } else { queue[0] = rest }
            day += 1
            skipFullDays()
        }
        while !queue.isEmpty {
            guard day < days.count else {
                for unit in queue { place(unit, nil) }
                break
            }
            let front = need(queue[0], day)
            if front == 0 || load[day] + front <= capacity[day] {
                place(queue.removeFirst(), day)
                if load[day] >= capacity[day] { day += 1; skipFullDays() }
                continue
            }
            // The front cluster doesn't fit in what's left of the day.
            if load[day] == 0 { splitFront(); continue }                                   // bigger than a whole day
            if load[day] >= days[day].target { day += 1; skipFullDays(); continue }       // day's done; it starts tomorrow
            // Short of target. If the cluster only takes the day a little over (about 20% over target in all), it goes on
            // whole and round order is kept.
            if load[day] + front <= capacity[day] + days[day].target / 10 {
                place(queue.removeFirst(), day)
                day += 1
                skipFullDays()
                continue
            }
            // Otherwise it starts tomorrow, and a later cluster that fits fills the gap.
            if let later = queue.indices.dropFirst().prefix(6).first(where: { index in
                let size = need(queue[index], day)
                return size > 0 && load[day] + size <= capacity[day]
            }) {
                place(queue.remove(at: later), day)
                if load[day] >= capacity[day] { day += 1; skipFullDays() }
                continue
            }
            splitFront()                                                                  // nothing fits: split it
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
