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
    @AppStorage(AutoBackup.lastKey) private var lastAuto = 0.0
    @AppStorage(AutoBackup.exportedKey) private var lastExported = 0.0
    @AppStorage(AutoBackup.folderNameKey) private var folderName = ""
    @AppStorage(AutoBackup.folderLastKey) private var folderLast = 0.0
    @AppStorage(AutoBackup.folderErrorKey) private var folderError = ""
    @State private var isChoosingFolder = false

    var body: some View {
        OptionalNavigationStack(embedded: embedded) {
            List {
                Section("Data") {
                    LabeledContent("Customers", value: "\(customers.count)")
                    LabeledContent("Visits", value: "\((try? modelContext.fetchCount(FetchDescriptor<Visit>())) ?? 0)")
                }

                Section("About") {
                    LabeledContent("Version", value: ChangeLog.currentVersion)
                    NavigationLink("What's New") { WhatsNewView() }
                }

                if let settings = settings.first {
                    RoundSettingsSections(settings: settings, crews: crews)
                }

                Section { QuickTourButton() } footer: { Text("A short animated tour of how the app works.") }

                CalendarSection()

                MessageSection()

                OwedReminderSection()


                Section {
                    LabeledContent("Saved on this phone") {
                        Text(lastAuto > 0 ? Date(timeIntervalSince1970: lastAuto).formatted(date: .abbreviated, time: .shortened) : "Not yet")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Backup folder") {
                        Text(folderName.isEmpty ? "Not set" : folderName).foregroundStyle(folderError.isEmpty ? Color.secondary : Color.notPaidText)
                    }
                    if !folderName.isEmpty {
                        LabeledContent("Last copied there") {
                            Text(folderError.isEmpty ? (folderLast > 0 ? Date(timeIntervalSince1970: folderLast).formatted(date: .abbreviated, time: .shortened) : "Not yet") : folderError)
                                .foregroundStyle(folderError.isEmpty ? Color.secondary : Color.notPaidText)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Button(folderName.isEmpty ? "Choose a backup folder..." : "Choose a different folder...") { isChoosingFolder = true }
                    if !folderName.isEmpty {
                        Button("Stop saving to a folder", role: .destructive) { AutoBackup.clearFolder() }
                    }
                    LabeledContent("Exported by hand") {
                        Text(lastExported > 0 ? Date(timeIntervalSince1970: lastExported).formatted(date: .abbreviated, time: .omitted) : "Never")
                            .foregroundStyle(.secondary)
                    }
                    Button("Back up now") {
                        if AutoBackup.run(context: modelContext) != nil { message = "Backed up. It's in Files > On My iPhone > Splash Out > Backups > Daily." }
                        else { message = "Nothing to back up yet." }
                    }
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
                    InfoFooter(text: "A copy is saved on this phone every day.", title: "Backups", points: [
                        "Choose a backup folder in iCloud Drive or OneDrive and each day's copy goes there too, so a lost phone loses nothing.",
                        "This phone keeps the last 14 days.",
                        "Export backup saves one copy now.",
                        "Import replaces everything in the app. A backup is saved first.",
                        "Customers only brings in names, addresses, prices, notes and round order. No cleans or payments.",
                        "Backups hold customer details, so keep them somewhere private."])
                }
            }
            .sudsyBackground()
            .navigationTitle("Settings")
            .fileImporter(isPresented: $isShowingImporter, allowedContentTypes: [.json]) { result in
                handlePickedFile(result)
            }
            .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    do {
                        try AutoBackup.setFolder(url)
                        _ = AutoBackup.run(context: modelContext)
                        message = folderError.isEmpty ? nil : folderError     // success shows in the rows above
                    } catch { message = "Couldn't use that folder: \(error.localizedDescription)" }
                case .failure(let error): message = "Couldn't open that folder: \(error.localizedDescription)"
                }
            }
            .fileExporter(
                isPresented: $isShowingExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "splash-out-backup-\(RoundCalendar.fileStamp())"
            ) { result in
                switch result {
                case .failure(let error): message = "Export failed: \(error.localizedDescription)"
                case .success: lastExported = Date().timeIntervalSince1970
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
                     ? "Replaces everything with just the customers in the file: no cleans, payments, diary or tips. A backup is saved first."
                     : "Replaces all customers, visits, diary and tips with the file. A backup is saved first.")
            }
            .alert("Clear all cleaning history?", isPresented: $isConfirmingClear) {
                Button("Clear history", role: .destructive) { clearHistory() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes every clean, payment, diary entry and tip. Customers stay. A backup is saved first.")
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
            InfoFooter(text: "Sent from the Message button on the Round.", title: "Fill-ins", points: [
                "{name}: the customer's name",
                "{date}: the day, e.g. Tuesday 13 October",
                "{when}: \"tomorrow\" or \"on Tuesday\""])
        }
    }
}

private struct OwedReminderSection: View {
    @AppStorage(OwedReminder.templateKey) private var template = OwedReminder.defaultTemplate

    var body: some View {
        Section {
            TextField("Message", text: $template, axis: .vertical)
                .lineLimit(3...6)
            if template != OwedReminder.defaultTemplate {
                Button("Reset to the standard message") { template = OwedReminder.defaultTemplate }
            }
        } header: {
            Text("Reminder for money owed")
        } footer: {
            InfoFooter(text: "Offered when you skip someone who owes.", title: "Fill-ins", points: [
                "{name}: their name",
                "{amount}: what they owe, e.g. £32",
                "{cleans}: \"clean\" or \"2 cleans\""])
        }
    }
}

/// Shares the working diary through the phone's Calendar app.
private struct CalendarSection: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(CalendarSync.enabledKey) private var enabled = false
    @State private var message: String?
    @State private var working = false
    @State private var needsSettings = false

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
            InfoFooter(text: "Shows who's working each day in your Calendar app.", title: "Calendar", points: [
                "Covers the next four months: the crew, or Day off. No customers, targets or notes.",
                "Change days in the Diary here, not in Calendar.",
                "Switching it off deletes the calendar.",
                "To share it: in Calendar tap Calendars, the i next to Splash Out, then Add Person.",
                "For Android: turn on Public Calendar there and send the link. It adds to Google Calendar."])
        }
        .alert("Calendar", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            if needsSettings { Button("Open Settings") { openAppSettings() } }
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
            needsSettings = outcome == .notAllowed
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
            InfoFooter(text: "Tap a name to rename. Swipe to remove.", points: ["Only someone who isn't in a crew can be removed."])
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
                 ? "Add your team first, then a crew for each group that works together."
                 : "Each crew has a day target in pounds. Swipe to delete.")
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
            InfoFooter(text: "Sets each week's target.", title: "Usual week", points: [
                "A day outside the usual week counts as worked once enough houses are cleaned.",
                "Each extra day worked adds the extra-day crew's target."])
        }

        Section {
            Stepper("Houses for a worked day: \(settings.minHousesForWorkingDay)", value: $settings.minHousesForWorkingDay, in: 1...30)
            Stepper("Overbook allowance: \(percentBinding(\.overbook).wrappedValue)%", value: percentBinding(\.overbook), in: 0...50, step: 5)
            Stepper("Due again after: \(settings.nextUpHideWeeks) weeks", value: $settings.nextUpHideWeeks, in: 1...12)
            Stepper("Target round length: \(settings.targetRoundWeeks) weeks", value: $settings.targetRoundWeeks, in: 2...12)
            DatePicker("Records start", selection: $settings.recordsStart, displayedComponents: .date)
        } header: {
            Text("Counting and Next Up")
        } footer: {
            InfoFooter(text: "Round length sets the ideal figures on Stats.", title: "Target round length", points: [
                "How long a full round should take.",
                "Stats works out how big the round, and how quick the days, need to be to hit the weekly target in that time."])
        }

        Section {
            Stepper("Rise: \(percentBinding(\.priceRisePercent).wrappedValue)%", value: percentBinding(\.priceRisePercent), in: 1...25)
            Stepper("Rise due after: \(settings.priceRiseDueAfterMonths) months", value: $settings.priceRiseDueAfterMonths, in: 6...60, step: 6)
        } header: {
            Text("Price rise")
        } footer: {
            InfoFooter(text: "Rises due show on Stats and Price Rise.", title: "Price rise", points: [
                "Due when a price hasn't gone up for this many months.",
                "No rise logged? It counts from the first clean.",
                "New prices are rounded to the nearest pound."])
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
            .navigationTitle("New Crew")
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
