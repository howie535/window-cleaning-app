import Foundation

/// Connects the Next Up engine to real customers, crews, diary days and settings.
@MainActor
enum RoundPlanner {
    struct DayPlan: Identifiable {
        var id: Date { date }
        var date: Date
        var target: Decimal
        /// target x (1 + overbook): how much can be booked.
        var bookTo: Decimal
        var crewName: String
        var customers: [Customer]
        var total: Decimal { customers.reduce(0) { $0 + $1.price } }
    }

    struct Plan {
        var days: [DayPlan]
        /// Due customers who don't fit in the days available.
        var later: [Customer]
        /// Who was cleaned most recently (the plan starts after them).
        var pointer: Customer?
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

        // Candidates carry an index back into `customers`.
        let candidates = customers.enumerated().map { index, customer -> NextUp.Candidate in
            var lastCleaned: Date?
            var lastNotDue: Date?
            var lastVisit: Date?
            for visit in customer.allVisits {
                if lastVisit.map({ visit.date > $0 }) ?? true { lastVisit = visit.date }
                if visit.kind == .cleaned, lastCleaned.map({ visit.date > $0 }) ?? true { lastCleaned = visit.date }
                if visit.kind == .notDue, lastNotDue.map({ visit.date > $0 }) ?? true { lastNotDue = visit.date }
            }
            return NextUp.Candidate(
                key: index,
                sequence: customer.sequence,
                isListable: customer.status == .active || customer.status == .leaving,
                price: customer.price,
                everyOther: customer.everyOther,
                lastCleaned: lastCleaned,
                lastNotDue: lastNotDue,
                lastVisit: lastVisit
            )
        }

        let resolver = DayResolver(settings: settings, crews: crews, workDays: workDays, customers: customers)
        let days = NextUp.workingDays(from: today, calendar: calendar) { resolver.target(on: $0) }
        let overbook = Money.decimal(settings.overbook * 100) / 100
        let assignments = NextUp.assignProjected(
            NextUp.rotated(candidates),
            to: days,
            overbook: overbook,
            hideWeeks: settings.nextUpHideWeeks,
            calendar: calendar
        )

        var dayPlans = days.map {
            DayPlan(date: $0.date, target: $0.target, bookTo: $0.target * (1 + overbook),
                    crewName: resolver.crewName(on: $0.date), customers: [])
        }
        var later: [Customer] = []
        for assignment in assignments {
            let customer = customers[assignment.key]
            if let index = assignment.dayIndex { dayPlans[index].customers.append(customer) } else { later.append(customer) }
        }

        // One full round, no empty days on the end: they fill up as customers are cleaned or skipped.
        while dayPlans.count > 1, dayPlans.last?.customers.isEmpty == true { dayPlans.removeLast() }

        let pointer = NextUp.pointer(in: candidates).map { customers[$0.key] }
        return Plan(days: dayPlans, later: later, pointer: pointer)
    }

    /// The pace of the round: the average gap, in weeks, between a customer's last clean and the day the plan
    /// has them next. A customer who was cleaned 5 weeks ago and isn't scheduled until next week counts as 6.
    /// Every-other customers and anyone not cleaned before are left out.
    static func paceWeeks(of plan: Plan) -> (weeks: Decimal, customers: Int)? {
        var totalDays = 0, count = 0
        for day in plan.days {
            for customer in day.customers where !customer.everyOther {
                guard let last = customer.lastCleanDate else { continue }
                let gap = RoundCalendar.london.dateComponents([.day], from: last, to: day.date).day ?? 0
                guard gap > 0 else { continue }
                totalDays += gap
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return (Decimal(totalDays) / Decimal(count) / 7, count)
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
