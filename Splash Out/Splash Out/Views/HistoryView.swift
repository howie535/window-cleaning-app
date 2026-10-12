import SwiftUI
import SwiftData

/// Every visit logged, by day, with day totals. Filter by date range and search by name or address.
/// Tap a visit to correct or delete it.
struct HistoryView: View {
    @Environment(RoundClock.self) private var clock
    @Query(sort: \Visit.date, order: .reverse) private var visits: [Visit]

    enum Range: String, CaseIterable, Identifiable {
        case today = "Today", week = "This week", month = "This month", custom = "Dates"
        var id: String { rawValue }
    }

    @State private var range: Range = .week
    @State private var from = RoundCalendar.startOfDay()
    @State private var to = RoundCalendar.startOfDay()
    @State private var search = ""
    @State private var editing: Visit?

    private var calendar: Calendar { RoundCalendar.london }

    private var bounds: (from: Date, to: Date) {
        let today = clock.today
        switch range {
        case .today: return (today, today)
        case .week: return (WeekMetrics.monday(onOrBefore: today, calendar: calendar), today)
        case .month: return (calendar.date(from: calendar.dateComponents([.year, .month], from: today))!, today)
        case .custom:
            let a = RoundCalendar.startOfDay(from), b = RoundCalendar.startOfDay(to)
            return (min(a, b), max(a, b))
        }
    }

    private struct DayGroup: Identifiable {
        var date: Date
        var visits: [Visit]
        var id: Date { date }
        var cleaned: [Visit] { visits.filter { $0.kind == .cleaned } }
        var work: Decimal { cleaned.reduce(0) { $0 + $1.charged } }
        var paid: Decimal { cleaned.reduce(0) { $0 + $1.paid } }
    }

    private var groups: [DayGroup] {
        let (lower, upper) = bounds
        let term = search.trimmingCharacters(in: .whitespaces)
        let shown = visits.filter { visit in
            guard visit.date >= lower && visit.date <= upper, let customer = visit.customer else { return false }
            return term.isEmpty || customer.name.localizedCaseInsensitiveContains(term) || customer.address.localizedCaseInsensitiveContains(term)
        }
        return Dictionary(grouping: shown, by: \.date)
            .map { DayGroup(date: $0.key, visits: $0.value.sorted { ($0.customer?.sequence ?? 0) < ($1.customer?.sequence ?? 0) }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        let groups = groups
        let work = groups.reduce(Decimal(0)) { $0 + $1.work }
        let houses = groups.reduce(0) { $0 + $1.cleaned.count }

        List {
            Section {
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if range == .custom {
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("To", selection: $to, displayedComponents: .date)
                }
                LabeledContent("Work", value: work.pounds)
                LabeledContent("Houses cleaned", value: "\(houses)")
            }

            if groups.isEmpty {
                Text(search.isEmpty ? "Nothing logged in these dates." : "Nothing matches \"\(search)\" in these dates.")
                    .foregroundStyle(.secondary)
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.visits) { visit in
                        Button { editing = visit } label: { row(visit) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text(RoundCalendar.weekdayShort(group.date))
                        Spacer()
                        Text("\(group.cleaned.count) houses · \(group.work.pounds)")
                            .monospacedDigit()
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Name or address")
        .navigationTitle("History")
        .sheet(item: $editing) { visit in
            EditVisitView(visit: visit)
        }
    }

    private func row(_ visit: Visit) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.customer?.name ?? "").foregroundStyle(.primary)
                if let note = visit.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            switch visit.kind {
            case .cleaned:
                VStack(alignment: .trailing, spacing: 2) {
                    Text(visit.charged.pounds).monospacedDigit()
                    Text(visit.paid == 0 ? "Not paid" : (visit.paid < visit.charged ? "Part paid" : "Paid"))
                        .font(.caption)
                        .foregroundStyle(visit.paid == 0 ? .red : (visit.paid < visit.charged ? .orange : .green))
                }
            case .skipped:
                Text("Skipped").foregroundStyle(.secondary)
            case .notDue:
                Text("Not due").foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
