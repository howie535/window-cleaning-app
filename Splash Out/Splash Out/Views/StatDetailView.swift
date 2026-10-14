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
        /// For weekly averages: the finished days behind the bar, and their totals (for the summary).
        var days = 0
        var sumOfDays = 0.0
        var houses = 0
        var work = 0.0
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
                    ForEach(summary(shown), id: \.0) { row in
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
            // Finished days only: today's first few cleans would skew it.
            let days = stats.dayTotals.filter { $0.key < today && $0.value.houses > 0 }
            return weekly(days.map { ($0.key, double($0.value.work) / Double($0.value.houses), $0.value.houses, double($0.value.work)) })
        case .housesPerDay:
            let days = stats.dayTotals.filter { $0.key < today && $0.value.houses >= minHouses }
            return weekly(days.map { ($0.key, Double($0.value.houses), $0.value.houses, double($0.value.work)) })
        case .skipRate:
            var counts: [Date: (skipped: Int, total: Int)] = [:]
            for customer in customers where customer.status != .cancelled {
                for visit in customer.allVisits where visit.kind != .notDue && visit.date < today {
                    let month = calendar.date(from: calendar.dateComponents([.year, .month], from: visit.date))!
                    counts[month, default: (0, 0)].total += 1
                    if visit.kind == .skipped { counts[month, default: (0, 0)].skipped += 1 }
                }
            }
            return counts.keys.sorted().map { month in
                var point = Point(date: month, value: Double(counts[month]!.skipped) / Double(max(1, counts[month]!.total)) * 100)
                point.days = counts[month]!.total        // visits
                point.houses = counts[month]!.skipped    // skips
                return point
            }
        }
    }

    /// Days grouped into weeks: each week's average of its days, with the average of the last 4 weeks alongside.
    private func weekly(_ days: [(date: Date, value: Double, houses: Int, work: Double)]) -> [Point] {
        var byWeek: [Date: [(date: Date, value: Double, houses: Int, work: Double)]] = [:]
        for day in days { byWeek[WeekMetrics.monday(onOrBefore: day.date, calendar: calendar), default: []].append(day) }
        var points = byWeek.keys.sorted().map { week -> Point in
            let list = byWeek[week]!
            let sum = list.reduce(0) { $0 + $1.value }
            var point = Point(date: week, value: sum / Double(list.count))
            point.days = list.count
            point.sumOfDays = sum
            point.houses = list.reduce(0) { $0 + $1.houses }
            point.work = list.reduce(0) { $0 + $1.work }
            return point
        }
        for index in points.indices {
            let window = points[max(0, index - 3)...index]
            points[index].second = window.reduce(0) { $0 + $1.sumOfDays } / Double(max(1, window.reduce(0) { $0 + $1.days }))
        }
        return points
    }

    // MARK: Chart

    @ViewBuilder
    private func chart(_ points: [Point]) -> some View {
        switch metric {
        case .weeklyWork:
            Chart {
                ForEach(points) { point in
                    BarMark(x: .value("Week", point.date, unit: .weekOfYear), y: .value("Work", point.value), width: ChartStyle.barWidth)
                        .cornerRadius(ChartStyle.cornerRadius)
                        .foregroundStyle(ChartStyle.barFill(short: point.second.map { point.value < $0 } ?? false))
                }
                ForEach(points.filter { $0.second != nil }) { point in
                    ChartStyle.targetMark(week: point.date, target: point.second ?? 0)
                }
            }
            .chartAxes(.money)
        case .monthlyWork:
            Chart(points) { point in
                BarMark(x: .value("Month", point.date, unit: .month), y: .value("Work", point.value), width: ChartStyle.barWidth)
                    .cornerRadius(ChartStyle.cornerRadius)
                    .foregroundStyle(ChartStyle.barFill())
            }
            .chartAxes(.money, months: true)
        case .skipRate:
            // Skips ÷ visits over the whole range (as the card), not an average of the months.
            let average = Double(points.reduce(0) { $0 + $1.houses }) / Double(max(1, points.reduce(0) { $0 + $1.days })) * 100
            Chart {
                ForEach(points) { point in
                    BarMark(x: .value("Month", point.date, unit: .month), y: .value("Skip rate", point.value), width: ChartStyle.barWidth)
                        .cornerRadius(ChartStyle.cornerRadius)
                        .foregroundStyle(ChartStyle.barFill())
                }
                RuleMark(y: .value("Average", average))
                    .lineStyle(ChartStyle.referenceStroke)
                    .foregroundStyle(ChartStyle.referenceColour)
            }
            .chartAxes(.percent, months: true)
        case .perHouse, .housesPerDay:
            let values = points.map(\.value)
            let low = (values.min() ?? 0), high = (values.max() ?? 0)
            let floor = max(0, low - (high - low) * 0.6 - 1)
            let overall = points.reduce(0) { $0 + $1.sumOfDays } / Double(max(1, points.reduce(0) { $0 + $1.days }))
            Chart {
                ForEach(points) { point in
                    BarMark(x: .value("Week", point.date, unit: .weekOfYear),
                            yStart: .value("Base", floor), yEnd: .value("Week", point.value), width: ChartStyle.barWidth)
                        .cornerRadius(ChartStyle.cornerRadius)
                        .foregroundStyle(ChartStyle.barFill())
                }
                ForEach(points) { point in
                    LineMark(x: .value("Week", point.date, unit: .weekOfYear), y: .value("4-week trend", point.second ?? point.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(ChartStyle.trendColour)
                        .lineStyle(ChartStyle.trendStroke)
                }
                RuleMark(y: .value("Average", overall))
                    .lineStyle(ChartStyle.referenceStroke)
                    .foregroundStyle(ChartStyle.referenceColour)
            }
            .chartYScale(domain: floor...(high + (high - low) * 0.15 + 0.5))
            .chartAxes(metric == .perHouse ? .money : .count)
        }
    }

    // MARK: Text

    private func money(_ value: Double) -> String {
        Decimal(value).formatted(.currency(code: "GBP").precision(.fractionLength(2)))
    }

    private func summary(_ points: [Point]) -> [(String, String)] {
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
            let days = points.reduce(0) { $0 + $1.days }
            let houses = points.reduce(0) { $0 + $1.houses }
            let work = points.reduce(0.0) { $0 + $1.work }
            return [("Worked days", "\(days)"), ("Average of the days", money(points.reduce(0) { $0 + $1.sumOfDays } / Double(max(1, days)))),
                    ("Per house overall", houses > 0 ? money(work / Double(houses)) : "–"),
                    ("Latest 4 weeks", money(points.last?.second ?? average))]
        case .housesPerDay:
            let days = points.reduce(0) { $0 + $1.days }
            let perDay = points.reduce(0) { $0 + $1.sumOfDays } / Double(max(1, days))
            return [("Worked days", "\(days)"), ("Average", perDay.formatted(.number.precision(.fractionLength(1)))),
                    ("Latest 4 weeks", (points.last?.second ?? average).formatted(.number.precision(.fractionLength(1))))]
        case .skipRate:
            let visits = points.reduce(0) { $0 + $1.days }, skips = points.reduce(0) { $0 + $1.houses }
            return [("Visits", "\(visits)"), ("Skipped", "\(skips)"),
                    ("Skip rate", (Double(skips) / Double(max(1, visits))).formatted(.percent.precision(.fractionLength(1))))]
        }
    }

    private var explanation: String {
        switch metric {
        case .weeklyWork: "Work charged each week; orange fell short. Dashed: the target."
        case .monthlyWork: "Work charged each month."
        case .perHouse: "Each week's £ per house. Line: 4-week trend. Dashed: average for the range."
        case .housesPerDay: "Houses per worked day each week. Line: 4-week trend. Dashed: average for the range."
        case .skipRate: "Skips as a share of visits each month. Dashed: average for the range."
        }
    }
}
