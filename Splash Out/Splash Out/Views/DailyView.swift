import SwiftUI
import SwiftData

/// One row per day with cleans, newest first, grouped by month, to go with Weekly. A day's £ a house shows orange
/// when it's below the 12-month average, so a busy day of cheap houses stands out. Tapping a day opens it.
struct DailyView: View {
    /// Only days from this date (the chart's range, or a week); nil for every day.
    var from: Date?
    /// Only days up to this date (a week's Sunday); nil for up to today.
    var through: Date?
    var title = "Daily"

    @Environment(RoundClock.self) private var clock
    @Query private var customers: [Customer]
    @Query private var visits: [Visit]
    @Query private var crews: [Crew]
    @Query private var workDays: [WorkDay]
    @Query private var settings: [AppSettings]

    var body: some View {
        let today = clock.today
        let stats = RoundStats(visits: visits, customers: customers, settings: settings.first, crews: crews, workDays: workDays, today: today)
        List {
            DaySections(stats: stats, today: today, from: from, through: through)
        }
        .navigationTitle(title)
    }
}

/// The days with cleans between two dates, newest first, one section per month, each opening its day.
struct DaySections: View {
    let stats: RoundStats
    let today: Date
    var from: Date?
    var through: Date?

    var body: some View {
        let average = stats.averagePerHouseByDay()
        let last = min(through ?? today, today)
        let days = stats.dayTotals.filter { $0.value.houses > 0 && $0.key <= last && $0.key >= (from ?? .distantPast) }
            .sorted { $0.key > $1.key }
        let calendar = RoundCalendar.london
        let months = Dictionary(grouping: days) { calendar.date(from: calendar.dateComponents([.year, .month], from: $0.key))! }

        if let average {
            Section {
            } footer: {
                Text("↓ Orange: under the \(Money.perHouse(average.average)) a house average (\(stats.analysisLabel)).")
            }
        }
        if days.isEmpty {
            Text("No cleans recorded.").foregroundStyle(.secondary)
        }
        ForEach(months.keys.sorted(by: >), id: \.self) { month in
            let list = months[month]!
            Section {
                ForEach(list, id: \.key) { day in
                    NavigationLink { DayView(date: day.key) } label: {
                        DayRow(date: day.key, totals: day.value, isToday: day.key == today, average: average?.average)
                    }
                }
            } header: {
                Text("\(month.formatted(.dateTime.month(.wide).year())) · \(list.count) day\(list.count == 1 ? "" : "s")")
            }
        }
    }
}

/// A day in a list: houses and £ a house on the left, the day's total on the right.
struct DayRow: View {
    let date: Date
    let totals: WeekMetrics.DayTotals
    var isToday = false
    var average: Decimal?

    var body: some View {
        let perHouse = totals.work / Decimal(max(1, totals.houses))
        let low = !isToday && average.map { perHouse < $0 } ?? false
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(RoundCalendar.weekdayShort(date) + (isToday ? " (so far)" : ""))
                    .font(.headline)
                HStack(spacing: 0) {
                    Text("\(totals.houses) house\(totals.houses == 1 ? "" : "s") · ")
                    if low { Image(systemName: "arrow.down").foregroundStyle(Color.notPaidText).accessibilityLabel("Below average") }
                    Text("\(Money.perHouse(perHouse)) a house").foregroundStyle(low ? Color.notPaidText : Color.secondary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(totals.work.pounds).font(.headline)
        }
        .padding(.vertical, 2)
    }
}

/// One day: houses, what was charged and the £ a house, then each customer cleaned in round order.
struct DayView: View {
    let date: Date
    @Query private var visits: [Visit]

    init(date: Date) {
        self.date = date
        let next = RoundCalendar.london.date(byAdding: .day, value: 1, to: date) ?? date
        _visits = Query(filter: #Predicate<Visit> { $0.date >= date && $0.date < next })
    }

    var body: some View {
        let cleaned = visits.filter { $0.kind == .cleaned && $0.customer != nil }
            .sorted { ($0.customer?.sequence ?? 0) < ($1.customer?.sequence ?? 0) }
        let skipped = visits.filter { $0.kind == .skipped }.count
        let work = cleaned.reduce(Decimal(0)) { $0 + $1.charged }
        let paid = cleaned.reduce(Decimal(0)) { $0 + $1.paid }
        let extras = cleaned.filter { $0.charged != $0.listPrice }.count

        List {
            Section {
                LabeledContent("Houses cleaned", value: "\(cleaned.count)")
                LabeledContent("Charged", value: work.pounds)
                LabeledContent("Average a house", value: cleaned.isEmpty ? "–" : Money.perHouse(work / Decimal(cleaned.count)))
                LabeledContent("Paid", value: paid.pounds)
                if skipped > 0 { LabeledContent("Skipped", value: "\(skipped)") }
            } footer: {
                if extras > 0 { Text("\(extras) charged a different amount from their list price (shown under their name).") }
            }
            if !cleaned.isEmpty {
                Section("Customers cleaned") {
                    ForEach(cleaned) { visit in
                        if let customer = visit.customer {
                            NavigationLink { CustomerDetailView(customer: customer) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(customer.name)
                                        Text(visit.charged != visit.listPrice
                                             ? "List \(visit.listPrice.pounds) · \(customer.area.isEmpty ? customer.round : customer.area)"
                                             : (customer.area.isEmpty ? customer.round : customer.area))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(visit.charged.pounds)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(RoundCalendar.weekdayShort(date))
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension Money {
    /// £ a house, always with pence (£16.72), as the Average price card shows it.
    static func perHouse(_ value: Decimal) -> String {
        value.formatted(.currency(code: "GBP").precision(.fractionLength(2)))
    }
}
