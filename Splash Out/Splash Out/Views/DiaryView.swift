import SwiftUI
import SwiftData

/// Month calendar showing who works each day. Tap a day to mark it off or change its crew.
/// Only days that differ from the usual week are stored (a day off, or a different crew).
struct DiaryView: View {
    @Query private var entries: [WorkDay]
    @Query private var crews: [Crew]
    @Query private var settings: [AppSettings]
    @Query private var customers: [Customer]
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var month = DiaryView.firstOfMonth(RoundCalendar.startOfDay())
    @State private var selected: DiaryDay?

    private struct DiaryDay: Identifiable {
        var date: Date
        var id: Date { date }
    }

    private static let calendar = RoundCalendar.london
    private static let weekdayTitles = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = RoundCalendar.london.timeZone
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    private static func firstOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }

    private func shiftMonth(_ delta: Int) {
        month = Self.calendar.date(byAdding: .month, value: delta, to: month) ?? month
    }

    /// Days of the month in grid order, with nil for the blanks before the 1st.
    private var cells: [Date?] {
        let calendar = Self.calendar
        let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let leading = (calendar.component(.weekday, from: month) + 5) % 7
        let dates = (0..<days).map { calendar.date(byAdding: .day, value: $0, to: month)! }
        return Array(repeating: nil, count: leading) + dates.map { Optional($0) }
    }

    var body: some View {
        let appSettings = settings.first ?? AppSettings()
        let resolver = RoundPlanner.DayResolver(settings: appSettings, crews: crews, workDays: entries, customers: customers)
        let byDate = Dictionary(entries.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let today = RoundCalendar.startOfDay()

        ScrollView {
            VStack(spacing: 14) {
                header
                weekdayRow
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                        if let date {
                            Button { selected = DiaryDay(date: date) } label: {
                                cell(for: date, entry: byDate[date], resolver: resolver, isToday: date == today)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(minHeight: sizeClass == .regular ? 84 : 58)
                        }
                    }
                }
                changesThisMonth(byDate: byDate)
                Text("Tap a day to mark a holiday or illness, or to change who is working. Days outside the usual week count as worked once enough houses are cleaned.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Diary")
        .sheet(item: $selected) { day in
            DiaryDayEditor(date: day.date, entry: byDate[day.date], crews: crews, settings: appSettings, resolver: resolver)
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
            Text(Self.monthFormatter.string(from: month))
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if month != Self.firstOfMonth(RoundCalendar.startOfDay()) {
                Button("Today") { month = Self.firstOfMonth(RoundCalendar.startOfDay()) }
                    .font(.footnote.weight(.semibold))
                    .offset(y: 14)
            }
        }
        .padding(.bottom, month != Self.firstOfMonth(RoundCalendar.startOfDay()) ? 10 : 0)
    }

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(Self.weekdayTitles, id: \.self) {
                Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private func initials(_ members: [String]) -> String {
        members.compactMap { $0.first.map(String.init) }.joined(separator: "+")
    }

    private func cell(for date: Date, entry: WorkDay?, resolver: RoundPlanner.DayResolver, isToday: Bool) -> some View {
        let target = resolver.target(on: date)
        let isOff = entry?.dayOff == true
        let crewName = resolver.crewName(on: date)
        let members = entry?.crewMembers.isEmpty == false
            ? entry!.crewMembers
            : (crews.first { $0.name == crewName }?.members ?? [])
        let changed = entry != nil
        let day = Self.calendar.component(.day, from: date)

        return VStack(spacing: 2) {
            Text("\(day)")
                .font(.subheadline.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .frame(width: 26, height: 26)
                .background(isToday ? Color.accentColor : Color.clear, in: Circle())
            if isOff {
                Text("Off").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
            } else if target > 0 {
                Text(initials(members)).font(.caption2.weight(.medium)).foregroundStyle(changed ? Color.accentColor : .secondary)
                if sizeClass == .regular {
                    Text(target.formatted(.currency(code: "GBP").precision(.fractionLength(0))))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: sizeClass == .regular ? 84 : 58)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isOff ? Color.orange.opacity(0.15) : (changed ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground)))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(RoundCalendar.weekdayShort(date)) \(day)")
        .accessibilityValue(isOff ? "Day off" : (target > 0 ? crewName : "Not working"))
    }

    private func changesThisMonth(byDate: [Date: WorkDay]) -> some View {
        let end = Self.calendar.date(byAdding: .month, value: 1, to: month)!
        let inMonth = entries.filter { $0.date >= month && $0.date < end }.sorted { $0.date < $1.date }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Changes this month").font(.headline)
            if inMonth.isEmpty {
                Text("None. The usual week applies.").foregroundStyle(.secondary)
            }
            ForEach(inMonth) { entry in
                Button { selected = DiaryDay(date: entry.date) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(RoundCalendar.weekdayShort(entry.date))
                                .foregroundStyle(.primary)
                            if let note = entry.note, !note.isEmpty {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(entry.dayOff ? "Day off" : (entry.crewMembers.isEmpty ? "Usual" : entry.crewMembers.joined(separator: " + ")))
                            .foregroundStyle(entry.dayOff ? .orange : .secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Edit one day. The crew is pre-filled with whoever is working that day.
private struct DiaryDayEditor: View {
    let date: Date
    let entry: WorkDay?
    let crews: [Crew]
    let settings: AppSettings
    let resolver: RoundPlanner.DayResolver

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var dayOff = false
    @State private var crewName = ""
    @State private var note = ""

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = RoundCalendar.london.timeZone
        formatter.dateFormat = "EEE d MMMM"
        return formatter
    }()

    private var usualCrew: String {
        let index = (RoundCalendar.london.component(.weekday, from: date) + 5) % 7
        return index < settings.usualWeek.count ? settings.usualWeek[index] : ""
    }

    private var weekdayName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = RoundCalendar.london.timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Day off (holiday or illness)", isOn: $dayOff)
                    if !dayOff {
                        Picker("Crew", selection: $crewName) {
                            Text("Not working").tag("")
                            ForEach(crews.sorted { $0.name < $1.name }) { Text($0.name).tag($0.name) }
                        }
                    }
                    LabeledField(label: "Note") { TextField("Optional", text: $note) }
                } footer: {
                    Text(usualCrew.isEmpty
                         ? "Nobody usually works on \(weekdayName)s."
                         : "The usual crew on \(weekdayName)s is \(usualCrew).")
                }

                if entry != nil {
                    Section {
                        Button("Back to the usual week", role: .destructive) {
                            if let entry { modelContext.delete(entry) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(Self.titleFormatter.string(from: date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear(perform: prefill)
        }
        .presentationDetents([.medium, .large])
    }

    private func prefill() {
        note = entry?.note ?? ""
        if let entry, entry.dayOff {
            dayOff = true
            crewName = usualCrew
            return
        }
        if let entry, !entry.crewMembers.isEmpty {
            crewName = crews.first { Set($0.members) == Set(entry.crewMembers) }?.name ?? ""
        } else {
            // Whoever is working that day, or nobody.
            crewName = resolver.target(on: date) > 0 ? resolver.crewName(on: date) : ""
        }
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue: String? = trimmed.isEmpty ? nil : trimmed

        var off = dayOff
        var members: [String] = []
        if !off {
            if crewName.isEmpty {
                // "Not working" only needs recording if the usual week says someone works.
                off = !usualCrew.isEmpty
            } else if crewName != usualCrew {
                members = crews.first { $0.name == crewName }?.members ?? []
            }
        }

        let isUsual = !off && members.isEmpty
        if isUsual && noteValue == nil {
            if let entry { modelContext.delete(entry) }
        } else if let entry {
            entry.dayOff = off
            entry.crewMembers = members
            entry.note = noteValue
        } else {
            modelContext.insert(WorkDay(date: date, dayOff: off, crewMembers: members, note: noteValue))
        }
        dismiss()
    }
}
