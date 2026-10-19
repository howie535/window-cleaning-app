import Foundation

/// Connects the Next Up engine to real customers, crews, diary days and settings.
@MainActor
enum RoundPlanner {
    /// One line of a day: a customer and how they stand (planned, booked, done today, greyed...).
    struct DayRow: Identifiable {
        var customer: Customer
        var state: NextUp.State
        /// Their cluster, and whether it has more than one customer on this day (shown with a bar down the side).
        var group: Int? = nil
        var inCluster = false
        var id: UUID { customer.id }
        /// Shown but not counted (not started yet, or an every-other customer's off round).
        var isPending: Bool { state == .notStarted || state == .everyOtherOff }
        var isDone: Bool { state == .cleanedToday || state == .skippedToday || state == .notDueToday }
    }

    struct DayPlan: Identifiable {
        var id: Date { date }
        var date: Date
        var target: Decimal
        /// target x (1 + overbook): how much can be booked.
        var bookTo: Decimal
        var crewName: String
        /// Customers still to do that day (planned or booked): what gets messaged and what's left.
        var customers: [Customer]
        /// Everything to show for the day in round order.
        var rows: [DayRow] = []
        /// Charged for cleans already done today.
        var doneTotal: Decimal = 0
        /// Still to do (planned and booked).
        var total: Decimal { customers.reduce(0) { $0 + $1.price } }
        var bookedCount: Int { rows.filter { $0.state == .booked }.count }
    }

    struct Plan {
        var days: [DayPlan]
        /// Due customers who don't fit in the days available.
        var later: [Customer]
        /// Where the round had got to at the start of today (the list carries on after them).
        var pointer: Customer?
        /// Typical days between cleans (used for every-other customers).
        var lapDays: Int
    }

    static func plan(
        customers: [Customer],
        settings: AppSettings?,
        crews: [Crew],
        workDays: [WorkDay],
        today: Date = RoundCalendar.startOfDay()
    ) -> Plan {
        let settings = settings ?? AppSettings()
        let calendar = RoundCalendar.london

        // Clusters: runs of neighbours in round order on the same street (or joined by hand). Paused and cancelled
        // customers don't break a run.
        let onRound = customers.indices.filter { customers[$0].status != .cancelled && customers[$0].status != .paused }
            .sorted { customers[$0].sequence < customers[$1].sequence }
        let groupNumbers = RoundGrouping.groups(onRound.map { (customers[$0].address, customers[$0].groupWithPrevious) })
        var groupOf: [Int: Int] = [:]
        for (position, index) in onRound.enumerated() { groupOf[index] = groupNumbers[position] }

        // Candidates carry an index back into `customers`.
        var regularCleans: [[Date]] = []
        let candidates = customers.enumerated().map { index, customer -> NextUp.Candidate in
            var lastCleaned: Date?
            var lastNotDue: Date?
            var lastVisit: Date?
            var lastVisitBeforeToday: Date?
            var visitedToday: VisitKind?
            var chargedToday: Decimal = 0
            var cleans: [Date] = []
            for visit in customer.allVisits {
                if lastVisit.map({ visit.date > $0 }) ?? true { lastVisit = visit.date }
                if visit.date < today, lastVisitBeforeToday.map({ visit.date > $0 }) ?? true { lastVisitBeforeToday = visit.date }
                if visit.kind == .cleaned {
                    cleans.append(visit.date)
                    if lastCleaned.map({ visit.date > $0 }) ?? true { lastCleaned = visit.date }
                }
                if visit.kind == .notDue, lastNotDue.map({ visit.date > $0 }) ?? true { lastNotDue = visit.date }
                if visit.date == today {
                    // A clean wins over a skip if both were logged today.
                    if visit.kind == .cleaned { visitedToday = .cleaned; chargedToday += visit.charged }
                    else if visitedToday == nil { visitedToday = visit.kind }
                }
            }
            if !customer.everyOther, customer.status == .active { regularCleans.append(cleans) }
            return NextUp.Candidate(
                key: index,
                sequence: customer.sequence,
                isListable: customer.status == .active || customer.status == .leaving,
                price: customer.price,
                everyOther: customer.everyOther,
                lastCleaned: lastCleaned,
                lastNotDue: lastNotDue,
                lastVisit: lastVisit,
                lastVisitBeforeToday: lastVisitBeforeToday,
                isPending: customer.status == .notStarted,
                visitedToday: visitedToday,
                chargedToday: chargedToday,
                bookedFor: customer.bookedFor.map { RoundCalendar.startOfDay($0) },
                group: groupOf[index]
            )
        }

        let resolver = DayResolver(settings: settings, crews: crews, workDays: workDays, customers: customers)
        var days = NextUp.workingDays(from: today, calendar: calendar) { resolver.target(on: $0) }
        // Today always shows if anything was done today, and a booked day always shows, even if it isn't a usual working day.
        var extraDates = Set<Date>()
        if candidates.contains(where: { $0.visitedToday != nil }) { extraDates.insert(today) }
        for c in candidates { if let booked = c.bookedFor, booked >= today { extraDates.insert(booked) } }
        for date in extraDates where !days.contains(where: { $0.date == date }) {
            days.append(NextUp.Day(date: date, target: resolver.target(on: date)))
        }
        days.sort { $0.date < $1.date }

        let overbook = Money.decimal(settings.overbook * 100) / 100
        let lapDays = NextUp.lapDays(cleanDates: regularCleans, today: today, fallback: 7 * settings.nextUpHideWeeks, calendar: calendar)
        let placements = NextUp.plan(candidates, days: days, today: today, overbook: overbook,
                                     hideWeeks: settings.nextUpHideWeeks, lapDays: lapDays, calendar: calendar)

        var dayPlans = days.map {
            DayPlan(date: $0.date, target: $0.target, bookTo: $0.target * (1 + overbook),
                    crewName: resolver.crewName(on: $0.date), customers: [])
        }
        var later: [Customer] = []
        for placement in placements.sorted(by: { $0.order < $1.order }) {
            let customer = customers[placement.key]
            if let index = placement.dayIndex {
                dayPlans[index].rows.append(DayRow(customer: customer, state: placement.state, group: groupOf[placement.key]))
                if placement.state.counts { dayPlans[index].customers.append(customer) }
                if placement.state == .cleanedToday { dayPlans[index].doneTotal += candidates[placement.key].chargedToday }
            } else if placement.state.counts {
                later.append(customer)
            }
        }

        // Mark rows that share their cluster with a neighbour on the same day.
        for d in dayPlans.indices {
            var counts: [Int: Int] = [:]
            for row in dayPlans[d].rows { if let g = row.group { counts[g, default: 0] += 1 } }
            for r in dayPlans[d].rows.indices { dayPlans[d].rows[r].inCluster = (dayPlans[d].rows[r].group.flatMap { counts[$0] } ?? 0) > 1 }
        }

        // One full round, no empty days on the end.
        while dayPlans.count > 1, dayPlans.last?.rows.isEmpty == true { dayPlans.removeLast() }

        let pointer = NextUp.startOfDayPointer(in: candidates).map { customers[$0.key] }
        return Plan(days: dayPlans, later: later, pointer: pointer, lapDays: lapDays)
    }

    /// Day targets and crews (Docs/SPEC.md 4.4).
    struct DayResolver {
        private let settings: AppSettings
        private let crews: [Crew]
        private let diary: [Date: WorkDay]
        private let cleanedPerDay: [Date: Int]

        init(settings: AppSettings, crews: [Crew], workDays: [WorkDay], customers: [Customer]) {
            self.settings = settings
            self.crews = crews
            self.diary = Dictionary(workDays.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
            var counts: [Date: Int] = [:]
            for customer in customers {
                for visit in customer.allVisits where visit.kind == .cleaned { counts[visit.date, default: 0] += 1 }
            }
            self.cleanedPerDay = counts
        }

        /// Monday = 0 ... Sunday = 6
        private func weekdayIndex(_ date: Date) -> Int {
            (RoundCalendar.london.component(.weekday, from: date) + 5) % 7
        }

        private func crew(named name: String) -> Crew? {
            name.isEmpty ? nil : crews.first { $0.name == name }
        }

        private func crew(members: [String]) -> Crew? {
            crews.first { Set($0.members) == Set(members) }
        }

        private func usualCrewName(on date: Date) -> String {
            let index = weekdayIndex(date)
            return index < settings.usualWeek.count ? settings.usualWeek[index] : ""
        }

        private var extraTarget: Decimal { crew(named: settings.extraDayCrew)?.dayTarget ?? 0 }

        func target(on date: Date) -> Decimal {
            let usual = crew(named: usualCrewName(on: date))?.dayTarget ?? 0
            if let entry = diary[date] {
                if entry.dayOff { return 0 }
                if !entry.crewMembers.isEmpty { return crew(members: entry.crewMembers)?.dayTarget ?? 0 }
                return usual > 0 ? usual : extraTarget
            }
            if usual > 0 { return usual }
            // A day outside the usual pattern counts once enough houses have been cleaned on it.
            return (cleanedPerDay[date] ?? 0) >= settings.minHousesForWorkingDay ? extraTarget : 0
        }

        func crewName(on date: Date) -> String {
            if let entry = diary[date], !entry.dayOff, !entry.crewMembers.isEmpty {
                return crew(members: entry.crewMembers)?.name ?? entry.crewMembers.joined(separator: " + ")
            }
            let usual = usualCrewName(on: date)
            return crew(named: usual)?.dayTarget ?? 0 > 0 ? usual : settings.extraDayCrew
        }
    }
}
