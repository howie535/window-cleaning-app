import SwiftUI
import SwiftData
import Charts

/// The dashboard (Docs/SPEC.md section 5): tiles for the week, today, ahead/behind, money owed and so on.
struct TodayView: View {
    @Query private var customers: [Customer]
    @Query private var crews: [Crew]
    @Query private var workDays: [WorkDay]
    @Query private var settings: [AppSettings]

    private func pounds(_ value: Decimal) -> String {
        value.formatted(.currency(code: "GBP").precision(.fractionLength(0)))
    }

    var body: some View {
        let today = RoundCalendar.startOfDay()
        let stats = RoundStats(customers: customers, settings: settings.first, crews: crews, workDays: workDays, today: today)
        let week = stats.thisWeek
        let ahead = stats.aheadBehind()
        let owed = RoundMetrics.moneyOwed(customers)
        let resolver = RoundPlanner.DayResolver(settings: settings.first ?? AppSettings(), crews: crews, workDays: workDays, customers: customers)
        let dayTarget = resolver.target(on: today)
        let todayWork = stats.work(from: today, through: today)
        let todayHouses = stats.houses(from: today, through: today)
        let oldestOwed = customers.flatMap { VisitLogger.unpaidVisits(for: $0) }.map(\.date).min()
        let taxYear = stats.currentTaxYear
        let yearTotals = RoundMetrics.totals(for: customers, in: TaxYear.range(startYear: taxYear))
        let listed = customers.filter { $0.status == .active || $0.status == .leaving }.count

        let tiles = LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12, alignment: .top)], spacing: 12) {
                    Tile(title: "This week", value: pounds(week.work),
                         detail: "of \(pounds(week.target)) target · \(week.houses) houses",
                         tint: week.work >= week.target ? .green : .primary)
                    Tile(title: "Today", value: pounds(todayWork),
                         detail: dayTarget > 0
                            ? "of \(pounds(dayTarget)) · \(resolver.crewName(on: today)) · \(todayHouses) houses"
                            : "Not a working day")
                    Tile(title: "Tax year \(TaxYear.label(startYear: taxYear))", value: pounds(yearTotals.work),
                         detail: "\(pounds(yearTotals.paid)) paid · \(pounds(yearTotals.work - yearTotals.paid)) not yet paid · \(yearTotals.cleans) cleans")
                    Tile(title: "Ahead / behind",
                         value: (ahead.difference >= 0 ? "+" : "-") + pounds(abs(ahead.difference)),
                         detail: "\(pounds(ahead.done)) done vs \(pounds(ahead.expected)) expected so far this tax year",
                         tint: ahead.difference >= 0 ? .green : .red,
                         caption: ahead.difference >= 0 ? "Ahead" : "Behind")
                    Tile(title: "Money owed", value: pounds(owed.amount),
                         detail: "\(owed.cleans) cleans" + (oldestOwed.map { " · oldest \(RoundCalendar.short($0))" } ?? ""),
                         tint: owed.amount > 0 ? .red : .primary)
                    Tile(title: "This month", value: pounds(stats.work(from: stats.thisMonthStart, through: today)),
                         detail: "so far · \(stats.houses(from: stats.thisMonthStart, through: today)) houses")
                    Tile(title: "Round value", value: pounds(RoundMetrics.roundValue(customers)),
                         detail: "per cycle (EO at half)" + (stats.cycleWeeks.map { " · about \($0.formatted(.number.precision(.fractionLength(1)))) weeks round" } ?? ""))
                    Tile(title: "Customers", value: "\(listed)",
                         detail: "\(customers.filter { $0.status == .notStarted }.count) not started · \(customers.filter { $0.status == .paused }.count) paused")
                    Tile(title: "New vs lost", value: "\(stats.newCustomers(taxYear: taxYear)) / \(stats.lostCustomers(taxYear: taxYear))",
                         detail: "new / cancelled this tax year")
                    Tile(title: "Price rises due", value: "\(stats.risesDue().count)",
                         detail: "no rise in \((settings.first?.priceRiseDueAfterMonths ?? 24) / 12) years · see Price Rise")
                    Tile(title: "Skip rate", value: stats.skipRate.formatted(.percent.precision(.fractionLength(1))),
                         detail: "of each customer's last 6 visits")
                }

        NavigationStack {
            GeometryReader { geometry in
                // Wide enough (iPad landscape): tiles on the left, the chart beside them.
                let sideBySide = geometry.size.width > 800
                ScrollView {
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
                        WeeksChart(weeks: Array(stats.weeks.suffix(12)))
                            .padding()
                    }
                }
            }
            .navigationTitle("Today")
            .background(Color(.systemGroupedBackground))
        }
    }
}

private struct Tile: View {
    let title: String
    let value: String
    let detail: String
    var tint: Color = .primary
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
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
