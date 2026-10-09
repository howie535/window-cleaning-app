import SwiftUI
import SwiftData

/// Optional diary: only days that differ from the usual week (a day off, or a different crew).
struct DiaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkDay.date, order: .reverse) private var entries: [WorkDay]
    @Query private var crews: [Crew]

    @State private var editing: WorkDay?
    @State private var isAdding = false

    var body: some View {
        List {
            Section {
                if entries.isEmpty { Text("No diary entries. The usual week applies.").foregroundStyle(.secondary) }
                ForEach(entries) { entry in
                    Button { editing = entry } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(RoundCalendar.weekdayShort(entry.date) + " " + String(RoundCalendar.london.component(.year, from: entry.date)))
                                    .font(.headline).foregroundStyle(.primary)
                                if let note = entry.note, !note.isEmpty {
                                    Text(note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(entry.dayOff ? "Day off" : (entry.crewMembers.isEmpty ? "Usual" : entry.crewMembers.joined(separator: " + ")))
                                .foregroundStyle(entry.dayOff ? .orange : .secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { modelContext.delete(entries[index]) }
                }
            } footer: {
                Text("Log a holiday or illness (lowers that week's target) or an unusual crew. Working days are picked up from the cleans automatically.")
            }
        }
        .navigationTitle("Diary")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: { Label("Add entry", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $isAdding) { DiaryEditor(entry: nil, crews: crews) }
        .sheet(item: $editing) { DiaryEditor(entry: $0, crews: crews) }
    }
}

private struct DiaryEditor: View {
    let entry: WorkDay?
    let crews: [Crew]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var dayOff = false
    @State private var crewName = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Toggle("Day off (holiday or illness)", isOn: $dayOff)
                if !dayOff {
                    Picker("Crew", selection: $crewName) {
                        Text("Usual crew").tag("")
                        ForEach(crews.sorted { $0.name < $1.name }) { Text($0.name).tag($0.name) }
                    }
                }
                LabeledField(label: "Note") { TextField("Optional", text: $note) }
            }
            .navigationTitle(entry == nil ? "New entry" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear {
                guard let entry else { return }
                date = entry.date
                dayOff = entry.dayOff
                crewName = crews.first { Set($0.members) == Set(entry.crewMembers) }?.name ?? ""
                note = entry.note ?? ""
            }
        }
    }

    private func save() {
        let day = RoundCalendar.startOfDay(date)
        let members = dayOff ? [] : (crews.first { $0.name == crewName }?.members ?? [])
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let entry {
            entry.date = day
            entry.dayOff = dayOff
            entry.crewMembers = members
            entry.note = trimmed.isEmpty ? nil : trimmed
        } else {
            modelContext.insert(WorkDay(date: day, dayOff: dayOff, crewMembers: members, note: trimmed.isEmpty ? nil : trimmed))
        }
        dismiss()
    }
}
