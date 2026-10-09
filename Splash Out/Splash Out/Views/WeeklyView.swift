import SwiftUI
import SwiftData

/// One row per week from records start (Docs/SPEC.md section 5), with crew averages underneath.
struct WeeklyView: View {
    @Query private var customers: [Customer]
    @Query private var crews: [Crew]
    @Query private var workDays: [WorkDay]
    @Query private var settings: [AppSettings]

    private func pounds(_ value: Decimal) -> String {
        value.formatted(.currency(code: "GBP").precision(.fractionLength(0)))
    }

    /// Green when work meets target, amber within 10% below, red lower.
    private func colour(for week: WeekMetrics.Week) -> Color {
        if week.target == 0 { return .secondary }
        if week.work >= week.target { return .green }
        if week.work >= week.target * Decimal(string: "0.9")! { return .orange }
        return .red
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
        let today = RoundCalendar.startOfDay()
        let stats = RoundStats(customers: customers, settings: settings.first, crews: crews, workDays: workDays, today: today)

        List {
            Section {
                ForEach(stats.weeks.reversed(), id: \.start) { week in
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
                            Text(pounds(week.work))
                                .font(.headline)
                                .foregroundStyle(colour(for: week))
                            Text("target \(pounds(week.target))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
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
        .navigationTitle("Weekly")
    }
}
