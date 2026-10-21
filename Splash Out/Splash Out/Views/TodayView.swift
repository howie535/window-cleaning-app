import SwiftUI
import SwiftData
import Charts

/// The dashboard (Docs/SPEC.md section 5): tiles for the week, today, money owed and so on.
struct TodayView: View {
    @Environment(RoundClock.self) private var clock
    /// nil outside the tab bar (always shown).
    @Environment(TabState.self) private var tabs: TabState?
    @Query private var customers: [Customer]
    @Query private var visits: [Visit]
    @Query private var crews: [Crew]
    @Query private var workDays: [WorkDay]
    @Query private var settings: [AppSettings]
    @State private var destination: Destination?

    private func pounds2(_ value: Decimal) -> String {
        value.formatted(.currency(code: "GBP").precision(.fractionLength(2)))
    }

    private func pounds(_ value: Decimal) -> String {
        value.pounds
    }

    var body: some View {
        // Hidden tabs stay alive; skip the sums until this tab is showing again.
        if tabs == nil || tabs?.selection == .today {
            content
        } else {
            Color(.systemGroupedBackground)
        }
    }

    @ViewBuilder
    private var content: some View {
        let perfStart = PerfProbe.now()
        let today = clock.today
        let _ = VisitLookup.begin(visits)
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
        let average = RoundMetrics.averagePrice(customers)
        let listed = RoundMetrics.onRound(customers).count
        let rate = stats.workRate()
        let ideal = Ideal.current(stats: stats, customers: customers, weeks: settings.first?.targetRoundWeeks ?? 5)
        let gap = stats.roundLengthWeeks()
        let onRoundList = customers.filter { ($0.status == .active || $0.status == .leaving) && $0.price > 0 }
        let riseMonths = settings.first?.priceRiseDueAfterMonths ?? 24
        let risesKnown = onRoundList.filter { $0.priceSince != nil && PriceRise.isDue(priceSince: $0.priceSince, today: today, dueAfterMonths: riseMonths, calendar: RoundCalendar.london) }.count
        let noPriceDate = onRoundList.filter { $0.priceSince == nil }.count
        let risesSet = customers.filter { $0.pendingPrice != nil }
        let risesNotTold = risesSet.filter { $0.pendingPriceToldAt == nil }.count
        let notStarted = customers.filter { $0.status == .notStarted }.count
        let everyOther = customers.filter { ($0.status == .active || $0.status == .leaving) && $0.everyOther }.count
        let _ = PerfProbe.end("Stats", perfStart)
        let newVsLost = "\(stats.newCustomers(taxYear: taxYear)) / \(stats.lostCustomers(taxYear: taxYear))"
        let risesDueCount = risesKnown
        let _ = VisitLookup.end()
        let showIdeal = { destination = .ideal }
        let tiles = LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12, alignment: .top)], spacing: 12) {
                    card(.weeklyWork, Tile(title: "This week", value: pounds(week.work),
                         detail: "of \(pounds(week.target)) · \(week.houses) houses",
                         tint: week.work >= week.target ? .green : .primary))
                    card(nil, Tile(title: "Today", value: pounds(todayWork),
                         detail: dayTarget > 0 ? "of \(pounds(dayTarget)) · \(todayHouses) houses" : "Not a working day"))
                    card(.taxYear, Tile(title: "Tax year \(TaxYear.label(startYear: taxYear))", value: pounds(yearTotals.work),
                         detail: "\(pounds(yearTotals.paid)) paid · \(yearTotals.cleans) cleans"))
                    card(nil, Tile(title: "Money owed", value: pounds(owed.amount),
                         detail: "\(owed.cleans) cleans" + (oldestOwed.map { " · since \(RoundCalendar.short($0))" } ?? ""),
                         tint: owed.amount > 0 ? .red : .primary))
                    card(.monthlyWork, Tile(title: "This month", value: pounds(stats.work(from: stats.thisMonthStart, through: today)),
                         detail: "\(stats.houses(from: stats.thisMonthStart, through: today)) houses"))
                    card(nil, Tile(title: "Round value", value: pounds(RoundMetrics.roundValue(customers)),
                         detail: notStarted > 0 ? "per round · incl. \(notStarted) not started" : "per round",
                         ideal: ideal.roundValue.map { pounds($0) }, onIdeal: showIdeal))
                    card(.perHouse, Tile(title: "Average price per house",
                         value: pounds2(average.average),
                         detail: "list prices of \(average.customers) customers, no extras",
                         ideal: ideal.planned.map { pounds2($0.perHouse) }, onIdeal: showIdeal))
                    card(.housesPerDay, Tile(title: "Houses per workday",
                         value: rate.map { $0.housesPerDay.formatted(.number.precision(.fractionLength(1))) } ?? "–",
                         detail: rate.map { "over \($0.workedDays) days, \(stats.analysisLabel)" } ?? "no worked days yet"))
                    card(nil, Tile(title: "Round length",
                         value: gap.map { $0.weeks.formatted(.number.precision(.fractionLength(1))) + " weeks" } ?? "–",
                         detail: gap == nil ? "not enough history yet" : "average gap, last 12 weeks",
                         ideal: "\(ideal.weeks) weeks", onIdeal: showIdeal))
                    card(nil, Tile(title: "Customers", value: "\(listed)",
                         detail: "incl. \(notStarted) not started · \(everyOther) every-other · \(customers.filter { $0.status == .paused }.count) paused",
                         ideal: ideal.planned.map { "\($0.peopleNeeded)" }, onIdeal: showIdeal))
                    card(nil, Tile(title: "New vs lost", value: newVsLost,
                         detail: "this tax year"))
                    card(.priceRise, Tile(title: "Price rises due", value: "\(risesDueCount)",
                         detail: !risesSet.isEmpty
                            ? "\(risesSet.count) set" + (risesNotTold > 0 ? " · \(risesNotTold) not told" : " · all told")
                            : (noPriceDate > 0 ? "\(noPriceDate) with no price date" : "no rise in \(riseMonths / 12) years")))
                    card(.skipRate, Tile(title: "Skip rate", value: (rate?.skipRate ?? stats.skipRate).formatted(.percent.precision(.fractionLength(1))),
                             detail: rate == nil ? "all time" : stats.analysisLabel))
                }

        NavigationStack {
            GeometryReader { geometry in
                // Wide enough (iPad landscape): tiles on the left, the chart beside them.
                let sideBySide = geometry.size.width > 800
                ScrollView {
                    BackupReminder()
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                    if let started = startedToday(today) {
                        Label("\(started) new price\(started == 1 ? "" : "s") started today", systemImage: "arrow.up.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.purple)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
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
            .navigationTitle("Stats")
            .background(Color(.systemGroupedBackground))
            .navigationDestination(item: $destination) { destination in
                switch destination {
                case .weeklyWork: StatDetailView(metric: .weeklyWork)
                case .monthlyWork: StatDetailView(metric: .monthlyWork)
                case .perHouse: StatDetailView(metric: .perHouse)
                case .housesPerDay: StatDetailView(metric: .housesPerDay)
                case .skipRate: StatDetailView(metric: .skipRate)
                case .taxYear: TaxYearView()
                case .priceRise: PriceRiseView()
                case .ideal: IdealWorkingView(ideal: ideal)
                }
            }
        }
    }

    /// How many price rises switched over today, if any (saved by `PriceRise.applyDue`).
    private func startedToday(_ today: Date) -> Int? {
        guard let saved = UserDefaults.standard.string(forKey: PriceRise.lastAppliedKey) else { return nil }
        let parts = saved.split(separator: ":")
        guard parts.count == 2, String(parts[0]) == RoundCalendar.dayString(today) else { return nil }
        return Int(parts[1])
    }

    /// Where tapping a card (or an Ideal line) goes.
    enum Destination: Hashable {
        case weeklyWork, monthlyWork, perHouse, housesPerDay, skipRate, taxYear, priceRise, ideal
    }

    /// A card that opens `opens` when tapped (nil: not tappable). Its Ideal line has its own tap.
    private func card(_ opens: Destination?, _ tile: Tile) -> some View {
        var tile = tile
        tile.opens = opens != nil
        return tile.onTapGesture { if let opens { destination = opens } }
    }
}

struct Tile: View {
    let title: String
    let value: String
    let detail: String
    var tint: Color = .primary
    var caption: String?
    /// The figure needed to hit the target in the chosen round length.
    var ideal: String?
    var onIdeal: (() -> Void)? = nil
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
                Button { onIdeal?() } label: {
                    HStack(spacing: 4) {
                        Label("Target \(ideal)", systemImage: "scope")
                        Image(systemName: "info.circle")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                            y: .value("Work", NSDecimalNumber(decimal: week.work).doubleValue), width: ChartStyle.barWidth)
                        .cornerRadius(ChartStyle.cornerRadius)
                        .foregroundStyle(ChartStyle.barFill(short: week.target > 0 && week.work < week.target))
                }
                ForEach(weeks.filter { $0.target > 0 }, id: \.start) { week in
                    ChartStyle.targetMark(week: week.start, target: NSDecimalNumber(decimal: week.target).doubleValue)
                }
            }
            .chartAxes(.money, dateLabels: height > 200 ? 6 : 4)
            .frame(height: height)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
