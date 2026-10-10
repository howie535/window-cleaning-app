import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RoundBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Everything in Docs/SPEC.md section 2 "Settings", plus backup, import and export.
struct SettingsView: View {
    var embedded = false
    @Environment(\.modelContext) private var modelContext
    @Query private var customers: [Customer]
    @Query private var settings: [AppSettings]
    @Query(sort: \Crew.name) private var crews: [Crew]

    @State private var isShowingImporter = false
    @State private var importCustomersOnly = false
    @State private var pendingImportData: Data?
    @State private var isShowingExporter = false
    @State private var exportDocument = RoundBackupDocument(data: Data())
    @State private var isConfirmingClear = false
    @State private var message: String?

    var body: some View {
        OptionalNavigationStack(embedded: embedded) {
            List {
                Section("Your data") {
                    LabeledContent("Customers", value: "\(customers.count)")
                    LabeledContent("Visits", value: "\(customers.reduce(0) { $0 + $1.allVisits.count })")
                }

                if let settings = settings.first {
                    RoundSettingsSections(settings: settings, crews: crews)
                }

                CalendarSection()

                MessageSection()

                Section {
                    Button("Import round data...") {
                        importCustomersOnly = false
                        isShowingImporter = true
                    }
                    Button("Import customers only...") {
                        importCustomersOnly = true
                        isShowingImporter = true
                    }
                    Button("Export backup...") {
                        prepareExport()
                    }
                    Button("Clear all cleaning history...", role: .destructive) {
                        isConfirmingClear = true
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Importing replaces everything in the app, and a backup of the current data is saved first. \"Customers only\" brings in names, addresses, prices, notes and round order but no cleans or payments. Exported files contain customer details, so keep them somewhere safe such as OneDrive.")
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $isShowingImporter, allowedContentTypes: [.json]) { result in
                handlePickedFile(result)
            }
            .fileExporter(
                isPresented: $isShowingExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "splash-out-backup-\(RoundCalendar.fileStamp())"
            ) { result in
                if case .failure(let error) = result {
                    message = "Export failed: \(error.localizedDescription)"
                }
            }
            .alert(importCustomersOnly ? "Replace with customers only?" : "Replace all data?", isPresented: Binding(
                get: { pendingImportData != nil },
                set: { if !$0 { pendingImportData = nil } }
            )) {
                Button("Replace", role: .destructive) { runImport() }
                Button("Cancel", role: .cancel) { pendingImportData = nil }
            } message: {
                Text(importCustomersOnly
                     ? "This wipes everything currently in the app and loads only the customers from the file: no cleans, payments, diary or tips. A backup is saved first."
                     : "This wipes the customers, visits, diary and tips currently in the app and loads the file instead. A backup is saved first.")
            }
            .alert("Clear all cleaning history?", isPresented: $isConfirmingClear) {
                Button("Clear history", role: .destructive) { clearHistory() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every clean, payment, diary entry and tip. Customers, prices, notes and round order stay. A backup is saved first.")
            }
            .alert("Round data", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func prepareExport() {
        do {
            exportDocument = RoundBackupDocument(data: try ExportService.data(from: modelContext))
            isShowingExporter = true
        } catch {
            message = "Couldn't prepare the export: \(error.localizedDescription)"
        }
    }

    private func handlePickedFile(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            message = "Couldn't open that file: \(error.localizedDescription)"
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                pendingImportData = try Data(contentsOf: url)
            } catch {
                message = "Couldn't read that file: \(error.localizedDescription)"
            }
        }
    }

    private func runImport() {
        guard let data = pendingImportData else { return }
        pendingImportData = nil
        do {
            let summary = try ImportService.replaceAll(data: data, context: modelContext, includeHistory: !importCustomersOnly)
            var text = importCustomersOnly
                ? "Imported \(summary.customers) customers, with no cleaning history."
                : "Imported \(summary.customers) customers and \(summary.visits) visits."
            if summary.skippedVisits > 0 {
                text += " \(summary.skippedVisits) visits were left out because their dates weren't real."
            }
            if summary.backupURL != nil {
                text += " The previous data was backed up first."
            }
            message = text
        } catch {
            message = "Import failed, nothing was changed: \(error.localizedDescription)"
        }
    }

    private func clearHistory() {
        do {
            let summary = try ImportService.clearCleaningHistory(context: modelContext)
            message = "Removed \(summary.visits) visits, \(summary.diary) diary entries and \(summary.tips) tips. Customers were kept. A backup was saved first."
        } catch {
            message = "Couldn't clear the history: \(error.localizedDescription)"
        }
    }
}

/// The WhatsApp message sent to each day's customers (Round > Message).
private struct MessageSection: View {
    @AppStorage(DayMessage.templateKey) private var template = DayMessage.defaultTemplate

    var body: some View {
        Section {
            TextField("Message", text: $template, axis: .vertical)
                .lineLimit(3...6)
            if template != DayMessage.defaultTemplate {
                Button("Reset to the standard message") { template = DayMessage.defaultTemplate }
            }
            LabeledContent("Looks like") {
                Text(DayMessage.text(template: template, name: "Anne", date: RoundCalendar.london.date(byAdding: .day, value: 1, to: RoundCalendar.startOfDay())!))
                    .font(.footnote)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("WhatsApp message")
        } footer: {
            Text("Sent to everyone on a day from the Message button on the Round screen. {name} becomes the customer's name and {date} the day, like \"Tuesday 13 October\". {when} gives \"tomorrow\" or \"on Tuesday\" instead.")
        }
    }
}

/// Shares the working diary through the phone's Calendar app.
private struct CalendarSection: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(CalendarSync.enabledKey) private var enabled = false
    @State private var message: String?
    @State private var working = false

    var body: some View {
        Section {
            Toggle("Keep a calendar up to date", isOn: $enabled)
                .onChange(of: enabled) { _, on in
                    if on { run { await CalendarSync.sync(context: modelContext) } }
                    else { run { await CalendarSync.removeCalendar() } }
                }
            if enabled {
                Button(working ? "Updating..." : "Update calendar now") {
                    run { await CalendarSync.sync(context: modelContext) }
                }
                .disabled(working)
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text("Puts a \"Splash Out\" calendar in your Calendar app with who is working each day (the crew, or Day off), for the next four months. No targets, customers or notes. Switching it off deletes the calendar. It's one way: change the diary here, not in Calendar. To share it, open Calendar > Calendars, tap the i next to Splash Out, then Add Person. For someone on Android, turn on Public Calendar there and send them the link: they can add it to Google Calendar from its address.")
        }
        .alert("Calendar", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func run(_ work: @escaping () async -> CalendarSync.Outcome) {
        working = true
        Task {
            let outcome = await work()
            working = false
            message = outcome.message
            if outcome == .notAllowed { enabled = false }
        }
    }
}

/// Usual week, targets, Next Up rules and price rise settings.
private struct RoundSettingsSections: View {
    @Bindable var settings: AppSettings
    let crews: [Crew]

    @Environment(\.modelContext) private var modelContext
    @Query private var workDays: [WorkDay]
    @State private var newMemberName = ""
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var isAddingCrew = false
    @State private var teamMessage: String?

    private static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    private func percentBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Double>) -> Binding<Int> {
        Binding(
            get: { Int((settings[keyPath: keyPath] * 100).rounded()) },
            set: { settings[keyPath: keyPath] = Double($0) / 100 }
        )
    }

    private func crewTargetBinding(_ crew: Crew) -> Binding<String> {
        Binding(
            get: { NSDecimalNumber(decimal: crew.dayTarget).stringValue },
            set: { if let value = Decimal(string: $0), value >= 0 { crew.dayTarget = value } }
        )
    }

    private func addMember() {
        attempt {
            try TeamEditor.addMember(newMemberName, settings: settings)
            newMemberName = ""
        }
    }

    private func attempt(_ work: () throws -> Void) {
        do { try work() } catch { teamMessage = error.localizedDescription }
    }

    var body: some View {
        Section {
            ForEach(settings.teamMembers, id: \.self) { name in
                Button {
                    renameText = name
                    renaming = name
                } label: {
                    HStack {
                        Text(name).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "pencil").foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Remove", role: .destructive) {
                        attempt { try TeamEditor.removeMember(name, settings: settings, crews: crews) }
                    }
                }
            }
            LabeledField(label: "New team member") {
                TextField("Name", text: $newMemberName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(addMember)
            }
            Button("Add team member", action: addMember)
                .disabled(newMemberName.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Team")
        } footer: {
            Text("Everyone who works on the round. Tap a name to rename it, or swipe to remove someone who isn't in any crew.")
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let old = renaming {
                    attempt { try TeamEditor.renameMember(from: old, to: renameText, settings: settings, crews: crews, workDays: workDays) }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("Crews, the usual week and the diary follow the new name.")
        }
        .alert("Team", isPresented: Binding(get: { teamMessage != nil }, set: { if !$0 { teamMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(teamMessage ?? "")
        }
        .sheet(isPresented: $isAddingCrew) {
            NewCrewSheet(settings: settings, crews: crews)
        }

        Section {
            ForEach(crews) { crew in
                LabeledContent(crew.name) {
                    TextField("0", text: crewTargetBinding(crew))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        TeamEditor.deleteCrew(crew, settings: settings, context: modelContext)
                    }
                }
            }
            Button("Add a crew...") { isAddingCrew = true }
                .disabled(settings.teamMembers.isEmpty)
        } header: {
            Text("Crews and day targets")
        } footer: {
            Text(settings.teamMembers.isEmpty
                 ? "Add your team first, then make a crew for each combination of people who work together. Each crew has a target for how much work it does in a day."
                 : "A crew is a combination of people who work together, with the amount of work it aims to do in a day (in pounds). Swipe a crew to delete it.")
        }

        Section {
            ForEach(Array(Self.weekdays.enumerated()), id: \.offset) { index, day in
                Picker(day, selection: Binding(
                    get: { index < settings.usualWeek.count ? settings.usualWeek[index] : "" },
                    set: {
                        var week = settings.usualWeek
                        while week.count < 7 { week.append("") }
                        week[index] = $0
                        settings.usualWeek = week
                    }
                )) {
                    Text("Not working").tag("")
                    ForEach(crews) { Text($0.name).tag($0.name) }
                }
            }
            Picker("Extra-day crew", selection: $settings.extraDayCrew) {
                Text("None").tag("")
                ForEach(crews) { Text($0.name).tag($0.name) }
            }
        } header: {
            Text("Usual week")
        } footer: {
            Text("The usual week sets each week's target. A day outside it counts as worked once enough houses are cleaned, and adds the extra-day crew's target.")
        }

        Section("Counting and Next Up") {
            Stepper("Houses for a worked day: \(settings.minHousesForWorkingDay)", value: $settings.minHousesForWorkingDay, in: 1...30)
            Stepper("Overbook allowance: \(percentBinding(\.overbook).wrappedValue)%", value: percentBinding(\.overbook), in: 0...50, step: 5)
            Stepper("Due again after: \(settings.nextUpHideWeeks) weeks", value: $settings.nextUpHideWeeks, in: 1...12)
            DatePicker("Records start", selection: $settings.recordsStart, displayedComponents: .date)
        }

        Section {
            Toggle("Rise date set", isOn: Binding(
                get: { settings.priceRiseDate != nil },
                set: { settings.priceRiseDate = $0 ? (settings.priceRiseDate ?? PriceRise.previewDate(after: .now, calendar: RoundCalendar.london)) : nil }
            ))
            if settings.priceRiseDate != nil {
                DatePicker("Rise date", selection: Binding(
                    get: { settings.priceRiseDate ?? .now },
                    set: { settings.priceRiseDate = RoundCalendar.startOfDay($0) }
                ), displayedComponents: .date)
            }
            Stepper("Rise: \(percentBinding(\.priceRisePercent).wrappedValue)%", value: percentBinding(\.priceRisePercent), in: 1...30)
            Stepper("Delay if risen within: \(settings.priceRiseDelayMonths) months", value: $settings.priceRiseDelayMonths, in: 0...36)
            Stepper("Rise due after: \(settings.priceRiseDueAfterMonths) months", value: $settings.priceRiseDueAfterMonths, in: 6...60, step: 6)
        } header: {
            Text("Price rise")
        } footer: {
            Text("Leave the rise date off until it's decided: Price Rise then shows a preview for the next 6 April.")
        }
    }
}

/// Pick the people in a new crew and the day target for it.
private struct NewCrewSheet: View {
    let settings: AppSettings
    let crews: [Crew]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String> = []
    @State private var target = ""
    @State private var message: String?

    private var previewName: String {
        Crew.autoName(for: settings.teamMembers.filter { chosen.contains($0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Who is in this crew?") {
                    ForEach(settings.teamMembers, id: \.self) { name in
                        Toggle(name, isOn: Binding(
                            get: { chosen.contains(name) },
                            set: { if $0 { chosen.insert(name) } else { chosen.remove(name) } }
                        ))
                    }
                }
                Section {
                    LabeledField(label: "Day target (£)") {
                        TextField("e.g. 300", text: $target).keyboardType(.numberPad)
                    }
                } footer: {
                    Text(chosen.isEmpty ? "The crew is named after its people." : "This crew will be called \"\(previewName)\".")
                }
            }
            .navigationTitle("New crew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add", action: save) }
            }
            .alert("New crew", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        do {
            let value = Decimal(string: target.trimmingCharacters(in: .whitespaces)) ?? 0
            try TeamEditor.addCrew(members: chosen, dayTarget: value, settings: settings, crews: crews, context: modelContext)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: Customer.self, inMemory: true)
}
