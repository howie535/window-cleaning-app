import Foundation

/// Builds the Today, Weekly and Tax Year figures from the real data (Docs/SPEC.md 4.1 to 4.7, 4.12, 4.13).
@MainActor
struct RoundStats {
    let customers: [Customer]
    let settings: AppSettings
    let crews: [Crew]
    let workDays: [WorkDay]
    let today: Date

    private let calendar = RoundCalendar.london

    /// Cleaned visits per date.
    let dayTotals: [Date: WeekMetrics.DayTotals]
    let config: WeekMetrics.Config

    init(customers: [Customer], settings: AppSettings?, crews: [Crew], workDays: [WorkDay], today: Date = RoundCalendar.startOfDay()) {
        let settings = settings ?? AppSettings()
        self.customers = customers
        self.settings = settings
        self.crews = crews
        self.workDays = workDays
        self.today = today

        var totals: [Date: WeekMetrics.DayTotals] = [:]
        for customer in customers {
            for visit in customer.allVisits where visit.kind == .cleaned {
                totals[visit.date, default: .init()].houses += 1
                totals[visit.date, default: .init()].work += visit.charged
                totals[visit.date, default: .init()].paid += visit.paid
            }
        }
        dayTotals = totals

        let targets: [Decimal] = (0..<7).map { index in
            let name = index < settings.usualWeek.count ? settings.usualWeek[index] : ""
            return crews.first { $0.name == name && !name.isEmpty }?.dayTarget ?? 0
        }
        config = WeekMetrics.Config(
            usualTargets: targets,
            extraTarget: crews.first { $0.name == settings.extraDayCrew }?.dayTarget ?? 0,
            minHouses: settings.minHousesForWorkingDay,
            daysOff: Set(workDays.filter(\.dayOff).map(\.date))
        )
    }

    // MARK: Weeks

    var weeks: [WeekMetrics.Week] {
        WeekMetrics.weeks(from: settings.recordsStart, today: today, days: dayTotals, config: config, calendar: calendar)
    }

    var thisWeek: WeekMetrics.Week {
        WeekMetrics.week(starting: WeekMetrics.monday(onOrBefore: today, calendar: calendar), today: today, days: dayTotals, config: config, calendar: calendar)
    }

    // MARK: Tax year

    var currentTaxYear: Int { TaxYear.startYear(containing: today) }

    func aheadBehind(taxYear: Int? = nil) -> WeekMetrics.AheadBehind {
        let start = TaxYear.range(startYear: taxYear ?? currentTaxYear).lowerBound
        return WeekMetrics.aheadBehind(taxYearStart: start, today: today, days: dayTotals, config: config, calendar: calendar)
    }

    func months(taxYear: Int) -> [WeekMetrics.MonthRow] {
        WeekMetrics.monthRanges(taxYearStart: taxYear, calendar: calendar).map { range in
            var row = WeekMetrics.MonthRow(label: range.label, from: range.from, to: range.to)
            for customer in customers {
                for visit in customer.allVisits where visit.kind == .cleaned && visit.date >= range.from && visit.date <= range.to {
                    row.work += visit.charged
                    row.paid += visit.paid
                    row.notYetPaid += max(0, visit.charged - visit.paid)
                    row.cleans += 1
                    row.extras += max(0, visit.charged - visit.listPrice)
                }
            }
            let daysSoFar = max(0, (calendar.dateComponents([.day], from: range.from, to: min(today, range.to)).day ?? -1) + 1)
            if row.work > 0, daysSoFar > 0 {
                row.averagePerWeek = row.work / (Decimal(daysSoFar) / 7)
            }
            return row
        }
    }

    struct RoundRow: Equatable {
        var round: String
        var work: Decimal
        var paid: Decimal
        var notYetPaid: Decimal
        var cleans: Int
    }

    func rounds(taxYear: Int) -> [RoundRow] {
        let range = TaxYear.range(startYear: taxYear)
        var byRound: [String: RoundRow] = [:]
        for customer in customers {
            let name = customer.round.isEmpty ? "No round" : customer.round
            for visit in customer.allVisits where visit.kind == .cleaned && range.contains(visit.date) {
                var row = byRound[name] ?? RoundRow(round: name, work: 0, paid: 0, notYetPaid: 0, cleans: 0)
                row.work += visit.charged
                row.paid += visit.paid
                row.notYetPaid += max(0, visit.charged - visit.paid)
                row.cleans += 1
                byRound[name] = row
            }
        }
        return byRound.values.sorted { $0.round < $1.round }
    }

    // MARK: Today

    func work(from: Date, through: Date) -> Decimal {
        dayTotals.filter { $0.key >= from && $0.key <= through }.reduce(0) { $0 + $1.value.work }
    }

    func houses(from: Date, through: Date) -> Int {
        dayTotals.filter { $0.key >= from && $0.key <= through }.reduce(0) { $0 + $1.value.houses }
    }

    var thisMonthStart: Date {
        let comps = calendar.dateComponents([.year, .month], from: today)
        return calendar.date(from: comps)!
    }

    /// 4.7: round value divided by average weekly work over the last 8 weeks that had a target.
    var cycleWeeks: Decimal? {
        let thisMonday = WeekMetrics.monday(onOrBefore: today, calendar: calendar)
        let window = weeks.filter { $0.start >= calendar.date(byAdding: .day, value: -56, to: thisMonday)! && $0.start < thisMonday && $0.target > 0 }
        guard !window.isEmpty else { return nil }
        let average = window.reduce(Decimal(0)) { $0 + $1.work } / Decimal(window.count)
        guard average > 0 else { return nil }
        return RoundMetrics.roundValue(customers) / average
    }

    /// 4.12: first cleaned visit this tax year. For 2026-27 only, first cleans before 18 May 2026 are ignored,
    /// because records start in April 2026.
    func newCustomers(taxYear: Int) -> Int {
        let range = TaxYear.range(startYear: taxYear)
        let floor: Date? = taxYear == 2026 ? RoundCalendar.date(year: 2026, month: 5, day: 18) : nil
        return customers.filter { customer in
            guard let first = customer.allVisits.filter({ $0.kind == .cleaned }).map(\.date).min() else { return false }
            return range.contains(first) && (floor.map { first >= $0 } ?? true)
        }.count
    }

    func lostCustomers(taxYear: Int) -> Int {
        let range = TaxYear.range(startYear: taxYear)
        return customers.filter { $0.status == .cancelled && ($0.lastCleanDate.map(range.contains) ?? false) }.count
    }

    /// Skipped / (skipped + cleaned) across every visit ever recorded, for everyone except cancelled customers.
    /// "Not due" visits (an every-other customer's off round) don't count either way.
    var skipRate: Double {
        var skipped = 0, total = 0
        for customer in customers where customer.status != .cancelled {
            for visit in customer.allVisits where visit.kind != .notDue {
                total += 1
                if visit.kind == .skipped { skipped += 1 }
            }
        }
        return total == 0 ? 0 : Double(skipped) / Double(total)
    }

    /// Houses cleaned per worked day over a tax year so far (a worked day has at least the minimum houses).
    func housesPerWorkedDay(taxYear: Int) -> (average: Decimal, days: Int)? {
        let range = TaxYear.range(startYear: taxYear)
        var houses = 0, days = 0
        for (date, totals) in dayTotals where range.contains(date) && date <= today && totals.houses >= settings.minHousesForWorkingDay {
            houses += totals.houses
            days += 1
        }
        guard days > 0 else { return nil }
        return (Decimal(houses) / Decimal(days), days)
    }

    // MARK: Crew averages (4.13)

    struct CrewAverage: Equatable {
        var crew: String
        var days: Int
        var averagePerDay: Decimal
        var housesPerDay: Decimal
        var perHouse: Decimal
    }

    /// Diary days with a known crew (an override, or that weekday's usual crew), not days off, with work done.
    func crewAverages() -> [CrewAverage] {
        let resolver = RoundPlanner.DayResolver(settings: settings, crews: crews, workDays: workDays, customers: customers)
        var perCrew: [String: (days: Int, work: Decimal, houses: Int)] = [:]
        for entry in workDays where !entry.dayOff {
            guard let totals = dayTotals[entry.date], totals.work > 0 else { continue }
            let name = resolver.crewName(on: entry.date)
            var current = perCrew[name] ?? (0, 0, 0)
            current.days += 1
            current.work += totals.work
            current.houses += totals.houses
            perCrew[name] = current
        }
        return perCrew.map { name, value in
            CrewAverage(
                crew: name,
                days: value.days,
                averagePerDay: value.work / Decimal(value.days),
                housesPerDay: Decimal(value.houses) / Decimal(value.days),
                perHouse: value.houses == 0 ? 0 : value.work / Decimal(value.houses)
            )
        }.sorted { $0.crew < $1.crew }
    }
}
