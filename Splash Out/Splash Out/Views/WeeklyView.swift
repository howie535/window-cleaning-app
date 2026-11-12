import SwiftUI
import SwiftData

/// Weeks and days in one place (Docs/SPEC.md section 5). Weeks: one row per week from records start, each opening its
/// days, with crew averages underneath. Days: every day with cleans, by month.
struct WeeklyView: View {
    @Environment(RoundClock.self) private var clock
    @Query private var customers: [Customer]
    @Query private var visits: [Visit]
    @Query private var crews: [Crew]
    @Query private var workDays: [WorkDay]
    @Query private var settings: [AppSettings]

    enum Mode: String, CaseIterable { case weeks = "Weeks", days = "Days" }
    @State private var mode: Mode = .weeks

    private func pounds(_ value: Decimal) -> String {
        value.pounds
    }

    /// Green when work meets target, amber within 10% below, red lower.
    private func colour(for week: WeekMetrics.Week) -> Color {
        if week.target == 0 { return .secondary }
        if week.work >= week.target { return .paidText }
        if week.work >= week.target * Decimal(string: "0.9")! { return .notPaidText }
        return .owedText
    }

    /// A shape as well as the colour: met, nearly, short.
    private func symbol(for week: WeekMetrics.Week) -> String? {
        if week.target == 0 { return nil }
        if week.work >= week.target { return "checkmark.circle.fill" }
        if week.work >= week.target * Decimal(string: "0.9")! { return "minus.circle.fill" }
        return "arrow.down.circle.fill"
    }

    private func status(_ week: WeekMetrics.Week, today: Date, usualDaysInWeek: Int) -> String {
        let isPast = RoundCalendar.london.date(byAdding: .day, value: 6, to: week.start)! < today
        if isPast && week.daysWorked == 0 { return "Week off" }
        var text = "\(week.daysWorked) day\(week.daysWorked == 1 ? "" : "s")"
        if week.daysWorked > week.usualDays { text += " (extra day)" }
        if week.usualDays < usualDaysInWeek { text += " · day off logged" }
        return text
    }

    var body: some View {
        let today = clock.today
        let stats = RoundStats(visits: visits, customers: customers, settings: settings.first, crews: crews, workDays: workDays, today: today)

        List {
            Picker("Show", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if mode == .days {
                DaySections(stats: stats, today: today)
            } else {
            Section {
                ForEach(stats.weeks.reversed(), id: \.start) { week in
                    let sunday = RoundCalendar.london.date(byAdding: .day, value: 6, to: week.start)!
                    NavigationLink {
                        DailyView(from: week.start, through: sunday, title: "Week of \(RoundCalendar.short(week.start))")
                    } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Week of \(RoundCalendar.shortWithYear(week.start))")
                                .font(.headline)
                            Text(status(week, today: today, usualDaysInWeek: stats.config.usualTargets.filter { $0 > 0 }.count) + " · \(week.houses) houses")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                if let symbol = symbol(for: week) {
                                    Image(systemName: symbol).font(.subheadline)
                                        .accessibilityLabel(week.work >= week.target ? "Target met" : "Short of target")
                                }
                                Text(pounds(week.work))
                                    .font(.headline)
                            }
                            .foregroundStyle(colour(for: week))
                            Text("target \(pounds(week.target))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    }
                    .disabled(week.houses == 0)
                }
            } header: {
                Text("From \(RoundCalendar.shortWithYear((settings.first ?? AppSettings()).recordsStart))")
            }

            let averages = stats.crewAverages()
            if !averages.isEmpty {
                Section("Crew averages") {
                    ForEach(averages, id: \.crew) { crew in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(crew.crew).font(.headline)
                                Spacer()
                                Text("\(pounds(crew.averagePerDay)) a day")
                            }
                            Text("\(crew.days) days · \(crew.housesPerDay.formatted(.number.precision(.fractionLength(1)))) houses a day · \(crew.perHouse.formatted(.currency(code: "GBP").precision(.fractionLength(2)))) a house")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            }
        }
        .navigationTitle(mode == .weeks ? "Weekly" : "Daily")
    }
}
