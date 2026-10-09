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

/// Usual week, targets, Next Up rules and price rise settings.
private struct RoundSettingsSections: View {
    @Bindable var settings: AppSettings
    let crews: [Crew]

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

    var body: some View {
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
                ForEach(crews) { Text($0.name).tag($0.name) }
            }
        } header: {
            Text("Usual week")
        } footer: {
            Text("The usual week sets each week's target. A day outside it counts as worked once enough houses are cleaned, and adds the extra-day crew's target.")
        }

        Section("Crew day targets") {
            ForEach(crews) { crew in
                LabeledContent(crew.name) {
                    TextField("0", text: crewTargetBinding(crew))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }
        }

        Section("Counting and Next Up") {
            Stepper("Houses for a worked day: \(settings.minHousesForWorkingDay)", value: $settings.minHousesForWorkingDay, in: 1...30)
            Stepper("Overbook allowance: \(percentBinding(\.overbook).wrappedValue)%", value: percentBinding(\.overbook), in: 0...50, step: 5)
            Stepper("Hide if cleaned within: \(settings.nextUpHideWeeks) weeks", value: $settings.nextUpHideWeeks, in: 1...12)
            Stepper("Every-other: \(settings.nextUpHideWeeksEveryOther) weeks", value: $settings.nextUpHideWeeksEveryOther, in: 1...26)
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

#Preview {
    SettingsView()
        .modelContainer(for: Customer.self, inMemory: true)
}
