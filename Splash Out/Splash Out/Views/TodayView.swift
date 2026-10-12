import SwiftUI
import SwiftData
import Charts

/// The dashboard (Docs/SPEC.md section 5): tiles for the week, today, money owed and so on.
struct TodayView: View {
    @Environment(RoundClock.self) private var clock
    @Query private var customers: [Customer]
    @Query private var crews: [Crew]
    @Query private var workDays: [WorkDay]
    @Query private var settings: [AppSettings]

    private func pounds2(_ value: Decimal) -> String {
        value.formatted(.currency(code: "GBP").precision(.fractionLength(2)))
    }

    private func pounds(_ value: Decimal) -> String {
        value.pounds
    }

    var body: some View {
        let today = clock.today
        let stats = RoundStats(customers: customers, settings: settings.first, crews: crews, workDays: workDays, today: today)
        let week = stats.thisWeek
        let owed = RoundMetrics.moneyOwed(customers)
        let resolver = RoundPlanner.DayResolver(settings: settings.first ?? AppSettings(), crews: crews, workDays: workDays, customers: customers)
        let dayTarget = resolver.target(on: today)
        let todayWork = stats.work(from: today, through: today)
        let todayHouses = stats.houses(from: today, through: today)
        let oldestOwed = customers.flatMap { VisitLogger.unpaidVisits(for: $0) }.map(\.date).min()
        let taxYear = stats.currentTaxYear
        let yearTotals = RoundMetrics.totals(for: customers, in: TaxYear.range(startYear: taxYear))
        let plan = RoundPlanner.plan(customers: customers, settings: settings.first, crews: crews, workDays: workDays, today: today)
        let pace = RoundPlanner.paceWeeks(of: plan)
        let perDay = stats.housesPerWorkedDay(taxYear: taxYear)
        let perHouse = stats.averagePerHouseByDay(taxYear: taxYear)
        let priced = customers.filter { ($0.status == .active || $0.status == .leaving) && $0.price > 0 }
        let listAverage = priced.isEmpty ? Decimal(0) : priced.reduce(Decimal(0)) { $0 + $1.price } / Decimal(priced.count)
        let listed = customers.filter { $0.status == .active || $0.status == .leaving }.count
        let ideal = Ideal(stats: stats, weeks: settings.first?.targetRoundWeeks ?? 5, listAverage: listAverage,
                          housesPerDay: perDay?.average)

        let tiles = LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12, alignment: .top)], spacing: 12) {
                    NavigationLink { StatDetailView(metric: .weeklyWork) } label: {
                        Tile(title: "This week", value: pounds(week.work),
                             detail: "of \(pounds(week.target)) target · \(week.houses) houses",
                             tint: week.work >= week.target ? .green : .primary, opens: true)
                    }
                    Tile(title: "Today", value: pounds(todayWork),
                         detail: dayTarget > 0
                            ? "of \(pounds(dayTarget)) · \(resolver.crewName(on: today)) · \(todayHouses) houses"
                            : "Not a working day")
                    NavigationLink { TaxYearView() } label: {
                        Tile(title: "Tax year \(TaxYear.label(startYear: taxYear))", value: pounds(yearTotals.work),
                             detail: "\(pounds(yearTotals.paid)) paid · \(pounds(yearTotals.work - yearTotals.paid)) not yet paid · \(yearTotals.cleans) cleans",
                             opens: true)
                    }
                    Tile(title: "Money owed", value: pounds(owed.amount),
                         detail: "\(owed.cleans) cleans" + (oldestOwed.map { " · oldest \(RoundCalendar.short($0))" } ?? ""),
                         tint: owed.amount > 0 ? .red : .primary)
                    NavigationLink { StatDetailView(metric: .monthlyWork) } label: {
                        Tile(title: "This month", value: pounds(stats.work(from: stats.thisMonthStart, through: today)),
                             detail: "so far · \(stats.houses(from: stats.thisMonthStart, through: today)) houses", opens: true)
                    }
                    Tile(title: "Round value", value: pounds(RoundMetrics.roundValue(customers)),
                         detail: "per cycle", ideal: ideal.roundValue.map { pounds($0) })
                    NavigationLink { StatDetailView(metric: .perHouse) } label: {
                        Tile(title: "Average per house",
                             value: perHouse.map { pounds2($0.average) } ?? pounds2(listAverage),
                             detail: perHouse.map { "average of each day's £ per house, \($0.days) days this tax year (as the spreadsheet) · list prices \(pounds2(listAverage))" }
                                ?? "list price average across \(priced.count) customers",
                             ideal: ideal.perHouse.map { pounds2($0) }, opens: true)
                    }
                    NavigationLink { StatDetailView(metric: .housesPerDay) } label: {
                        Tile(title: "Houses per workday",
                             value: perDay.map { $0.average.formatted(.number.precision(.fractionLength(1))) } ?? "–",
                             detail: perDay.map { "over \($0.days) worked days this tax year · the work rate the ideal figures are based on" } ?? "no worked days yet this tax year",
                             opens: true)
                    }
                    Tile(title: "Pace",
                         value: pace.map { $0.weeks.formatted(.number.precision(.fractionLength(1))) + " weeks" } ?? "–",
                         detail: pace == nil ? "needs customers who have been cleaned before"
                                             : "between cleans on the current plan (every-other left out)",
                         ideal: "\(ideal.weeks) weeks")
                    Tile(title: "Customers", value: "\(listed)",
                         detail: "\(customers.filter { $0.status == .notStarted }.count) not started · \(customers.filter { $0.status == .paused }.count) paused",
                         ideal: ideal.customers.map { "\($0)" })
                    Tile(title: "New vs lost", value: "\(stats.newCustomers(taxYear: taxYear)) / \(stats.lostCustomers(taxYear: taxYear))",
                         detail: "new / cancelled this tax year")
                    NavigationLink { PriceRiseView() } label: {
                        Tile(title: "Price rises due", value: "\(stats.risesDue().count)",
                             detail: "no rise in \((settings.first?.priceRiseDueAfterMonths ?? 24) / 12) years", opens: true)
                    }
                    NavigationLink { StatDetailView(metric: .skipRate) } label: {
                        Tile(title: "Skip rate", value: stats.skipRate.formatted(.percent.precision(.fractionLength(1))), detail: "", opens: true)
                    }
                }
                .buttonStyle(.plain)

        NavigationStack {
            GeometryReader { geometry in
                // Wide enough (iPad landscape): tiles on the left, the chart beside them.
                let sideBySide = geometry.size.width > 800
                ScrollView {
                    BackupReminder()
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                    if sideBySide {
                        HStack(alignment: .top, spacing: 12) {
                            tiles
                                .frame(width: geometry.size.width * 0.5)
                            WeeksChart(weeks: Array(stats.weeks.suffix(12)), height: 420)
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    } else {
                        tiles
                            .padding(.horizontal)
                        if ideal.roundValue != nil {
                            Text("Ideal: what it takes to make the weekly target with a \(ideal.weeks)-week round at your current houses per workday, allowing for the skip rate. Change the round length in Settings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .padding(.top, 4)
                        }
                        WeeksChart(weeks: Array(stats.weeks.suffix(12)))
                            .padding()
                    }
                }
            }
            .navigationTitle("Stats")
            .background(Color(.systemGroupedBackground))
        }
    }
}

/// What the round needs to look like to hit the weekly target in the chosen round length.
struct Ideal {
    let weeks: Int
    /// Round value needed: weekly target × weeks, grossed up for skips.
    let roundValue: Decimal?
    let customers: Int?
    /// £ per house needed at the current work rate (houses per workday, which is taken as given).
    let perHouse: Decimal?

    @MainActor
    init(stats: RoundStats, weeks: Int, listAverage: Decimal, housesPerDay actualHouses: Decimal?) {
        self.weeks = weeks
        let targets = stats.config.usualTargets.filter { $0 > 0 }
        let weekly = targets.reduce(Decimal(0), +)
        guard weekly > 0 else {
            roundValue = nil; customers = nil; perHouse = nil
            return
        }
        let keep = Decimal(max(0.5, 1 - stats.skipRate))
        let value = weekly * Decimal(weeks) / keep
        roundValue = value
        customers = listAverage > 0 ? Int((NSDecimalNumber(decimal: value / listAverage).doubleValue).rounded(.up)) : nil
        let daily = weekly / Decimal(targets.count)
        perHouse = actualHouses.flatMap { $0 > 0 ? daily / $0 : nil }
    }
}

private struct Tile: View {
    let title: String
    let value: String
    let detail: String
    var tint: Color = .primary
    var caption: String?
    /// The figure needed to hit the target in the chosen round length.
    var ideal: String?
    /// Tapping opens more detail.
    var opens = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if opens {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.title.bold())
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let caption {
                    Text(caption).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                }
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ideal {
                Label("Ideal \(ideal)", systemImage: "scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Last 12 weeks: work as bars, target as a marker, so a short week is obvious at a glance.
private struct WeeksChart: View {
    let weeks: [WeekMetrics.Week]
    var height: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LAST 12 WEEKS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Chart {
                ForEach(weeks, id: \.start) { week in
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear),
                            y: .value("Work", NSDecimalNumber(decimal: week.work).doubleValue))
                        .foregroundStyle(week.work >= week.target ? Color.green : Color.orange)
                    if week.target > 0 {
                        let target = NSDecimalNumber(decimal: week.target).doubleValue
                        RectangleMark(x: .value("Week", week.start, unit: .weekOfYear),
                                      yStart: .value("Target", target - 14),
                                      yEnd: .value("Target", target + 14),
                                      width: .ratio(0.9))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: height > 200 ? 6 : 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: height)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
