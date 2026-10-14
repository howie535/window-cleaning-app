import SwiftUI
import SwiftData
import Charts

/// A Stats tile opened up: the figure over time, with a choice of range.
struct StatDetailView: View {
    enum Metric: String {
        case weeklyWork = "Work per week"
        case monthlyWork = "Work per month"
        case perHouse = "Average per house"
        case housesPerDay = "Houses per workday"
        case skipRate = "Skip rate"
    }

    enum Span: String, CaseIterable, Identifiable {
        case oneMonth = "1M", threeMonths = "3M", sixMonths = "6M", year = "12M", all = "All"
        var id: String { rawValue }

        /// Days back from today, or nil for everything.
        var days: Int? {
            switch self {
            case .oneMonth: 31
            case .threeMonths: 92
            case .sixMonths: 183
            case .year: 365
            case .all: nil
            }
        }
    }

    let metric: Metric

    @Environment(RoundClock.self) private var clock
    @Query private var customers: [Customer]
    @Query private var crews: [Crew]
    @Query private var workDays: [WorkDay]
    @Query private var settings: [AppSettings]

    @State private var span: Span = .year

    struct Point: Identifiable {
        var date: Date
        var value: Double
        /// Rolling average (lines) or target (weekly bars), when there is one.
        var second: Double?
        var id: Date { date }
    }

    private var calendar: Calendar { RoundCalendar.london }

    var body: some View {
        let today = clock.today
        let stats = RoundStats(customers: customers, settings: settings.first, crews: crews, workDays: workDays, today: today)
        let all = points(stats: stats, today: today)
        let from = span.days.flatMap { calendar.date(byAdding: .day, value: -$0, to: today) } ?? .distantPast
        let shown = all.filter { $0.date >= from }

        List {
            Section {
                Picker("Range", selection: $span) {
                    ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if shown.isEmpty {
                    Text("Nothing recorded in this range yet.").foregroundStyle(.secondary)
                } else {
                    chart(shown).frame(height: 260).padding(.vertical, 8)
                }
            } footer: {
                Text(explanation)
            }
            if !shown.isEmpty {
                Section("In this range") {
                    ForEach(summary(shown, dayTotals: stats.dayTotals), id: \.0) { row in
                        LabeledContent(row.0, value: row.1)
                    }
                }
            }
        }
        .navigationTitle(metric.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Data

    private func double(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }

    private func points(stats: RoundStats, today: Date) -> [Point] {
        let minHouses = settings.first?.minHousesForWorkingDay ?? 5
        switch metric {
        case .weeklyWork:
            let weeks = stats.weeks
            return weeks.map { Point(date: $0.start, value: double($0.work), second: $0.target > 0 ? double($0.target) : nil) }
        case .monthlyWork:
            var byMonth: [Date: Decimal] = [:]
            for (date, totals) in stats.dayTotals where date <= today {
                let month = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
                byMonth[month, default: 0] += totals.work
            }
            return byMonth.keys.sorted().map { Point(date: $0, value: double(byMonth[$0]!)) }
        case .perHouse:
            // Finished days only: today's first few cleans would skew the line.
            let days = stats.dayTotals.filter { $0.key < today && $0.value.houses > 0 }.sorted { $0.key < $1.key }
            return rolling(days.map { ($0.key, double($0.value.work) / Double($0.value.houses)) })
        case .housesPerDay:
            let days = stats.dayTotals.filter { $0.key < today && $0.value.houses >= minHouses }.sorted { $0.key < $1.key }
            return rolling(days.map { ($0.key, Double($0.value.houses)) })
        case .skipRate:
            var counts: [Date: (skipped: Int, total: Int)] = [:]
            for customer in customers where customer.status != .cancelled {
                for visit in customer.allVisits where visit.kind != .notDue && visit.date <= today {
                    let month = calendar.date(from: calendar.dateComponents([.year, .month], from: visit.date))!
                    counts[month, default: (0, 0)].total += 1
                    if visit.kind == .skipped { counts[month, default: (0, 0)].skipped += 1 }
                }
            }
            return counts.keys.sorted().map { Point(date: $0, value: Double(counts[$0]!.skipped) / Double(max(1, counts[$0]!.total)) * 100) }
        }
    }

    /// Each day's value with the average of the last 28 days (that day included) alongside.
    private func rolling(_ values: [(Date, Double)]) -> [Point] {
        values.enumerated().map { index, item in
            let start = calendar.date(byAdding: .day, value: -27, to: item.0)!
            let window = values[...index].filter { $0.0 >= start }.map(\.1)
            return Point(date: item.0, value: item.1, second: window.reduce(0, +) / Double(window.count))
        }
    }

    // MARK: Chart

    @ViewBuilder
    private func chart(_ points: [Point]) -> some View {
        let pounds = Decimal.FormatStyle.Currency(code: "GBP").precision(.fractionLength(0))
        let poundsAxis = AxisMarks { AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)); AxisValueLabel(format: pounds) }
        switch metric {
        case .weeklyWork:
            Chart {
                ForEach(points) { point in
                    let met = point.second.map { point.value >= $0 } ?? true
                    BarMark(x: .value("Week", point.date, unit: .weekOfYear), y: .value("Work", point.value), width: .ratio(0.7))
                        .cornerRadius(5)
                        .foregroundStyle(LinearGradient(colors: met ? [.green.opacity(0.65), .green] : [.orange.opacity(0.65), .orange],
                                                        startPoint: .bottom, endPoint: .top))
                }
                ForEach(points.filter { $0.second != nil }) { point in
                    LineMark(x: .value("Week", point.date, unit: .weekOfYear), y: .value("Target", point.second ?? 0))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .foregroundStyle(Color.primary.opacity(0.6))
                }
            }
            .chartYAxis { poundsAxis }
        case .monthlyWork:
            Chart(points) { point in
                BarMark(x: .value("Month", point.date, unit: .month), y: .value("Work", point.value), width: .ratio(0.7))
                    .cornerRadius(6)
                    .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.6), Color.accentColor], startPoint: .bottom, endPoint: .top))
            }
            .chartYAxis { poundsAxis }
        case .skipRate:
            Chart(points) { point in
                BarMark(x: .value("Month", point.date, unit: .month), y: .value("Skip rate %", point.value), width: .ratio(0.7))
                    .cornerRadius(6)
                    .foregroundStyle(LinearGradient(colors: [.orange.opacity(0.6), .orange], startPoint: .bottom, endPoint: .top))
            }
            .chartYAxis { AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))%") } }
            } }
        case .perHouse, .housesPerDay:
            let floor = (points.map(\.value).min() ?? 0) * 0.9
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Day", point.date, unit: .day),
                             yStart: .value("Floor", floor), yEnd: .value("28-day average", point.second ?? point.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                }
                ForEach(points) { point in
                    PointMark(x: .value("Day", point.date, unit: .day), y: .value("Each day", point.value))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .symbolSize(12)
                }
                ForEach(points) { point in
                    LineMark(x: .value("Day", point.date, unit: .day), y: .value("28-day average", point.second ?? point.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                if metric == .perHouse { poundsAxis } else { AxisMarks { AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)); AxisValueLabel() } }
            }
        }
    }

    // MARK: Text

    private func money(_ value: Double) -> String {
        Decimal(value).formatted(.currency(code: "GBP").precision(.fractionLength(2)))
    }

    private func summary(_ points: [Point], dayTotals: [Date: WeekMetrics.DayTotals]) -> [(String, String)] {
        let values = points.map(\.value)
        let average = values.reduce(0, +) / Double(values.count)
        switch metric {
        case .weeklyWork:
            let full = points.filter { ($0.second ?? 0) > 0 }
            let met = full.filter { $0.value >= ($0.second ?? 0) }.count
            return [("Weeks", "\(points.count)"), ("Average week", Decimal(average).pounds),
                    ("Best week", Decimal(values.max() ?? 0).pounds), ("Target met", "\(met) of \(full.count) weeks"),
                    ("Total", Decimal(values.reduce(0, +)).pounds)]
        case .monthlyWork:
            return [("Months", "\(points.count)"), ("Average month", Decimal(average).pounds), ("Total", Decimal(values.reduce(0, +)).pounds)]
        case .perHouse:
            let shownDays = Set(points.map(\.date))
            let totals = dayTotals.filter { shownDays.contains($0.key) }
            let houses = totals.values.reduce(0) { $0 + $1.houses }
            let work = totals.values.reduce(Decimal(0)) { $0 + $1.work }
            return [("Worked days", "\(points.count)"), ("Average of the days", money(average)),
                    ("Per house overall", houses > 0 ? (work / Decimal(houses)).formatted(.currency(code: "GBP").precision(.fractionLength(2))) : "–"),
                    ("Latest 28-day average", money(points.last?.second ?? average))]
        case .housesPerDay:
            return [("Worked days", "\(points.count)"), ("Average", average.formatted(.number.precision(.fractionLength(1)))),
                    ("Latest 28-day average", (points.last?.second ?? average).formatted(.number.precision(.fractionLength(1))))]
        case .skipRate:
            return [("Months", "\(points.count)"), ("Average month", (average / 100).formatted(.percent.precision(.fractionLength(1))))]
        }
    }

    private var explanation: String {
        switch metric {
        case .weeklyWork: "Work charged each week. Line: the target."
        case .monthlyWork: "Work charged each month."
        case .perHouse: "Dots: each day's £ per house. Line: 28-day average. The card averages the days, like the spreadsheet."
        case .housesPerDay: "Dots: houses each worked day. Line: 28-day average."
        case .skipRate: "Skips as a share of visits each month."
        }
    }
}
