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

/// Import and export of the whole round (Docs/SPEC.md section 6). More settings arrive in later stages.
struct SettingsView: View {
    var embedded = false
    @Environment(\.modelContext) private var modelContext
    @Query private var customers: [Customer]

    @State private var isShowingImporter = false
    @State private var pendingImportData: Data?
    @State private var isShowingExporter = false
    @State private var exportDocument = RoundBackupDocument(data: Data())
    @State private var message: String?

    var body: some View {
        OptionalNavigationStack(embedded: embedded) {
            List {
                Section("Your data") {
                    LabeledContent("Customers", value: "\(customers.count)")
                }

                Section {
                    Button("Import round data...") {
                        isShowingImporter = true
                    }
                    Button("Export backup...") {
                        prepareExport()
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Importing replaces everything in the app. A backup of the current data is saved first. Keep exported files somewhere safe such as OneDrive: they contain customer details.")
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
            .alert("Replace all data?", isPresented: Binding(
                get: { pendingImportData != nil },
                set: { if !$0 { pendingImportData = nil } }
            )) {
                Button("Replace", role: .destructive) { runImport() }
                Button("Cancel", role: .cancel) { pendingImportData = nil }
            } message: {
                Text("This wipes the customers, visits, diary and tips currently in the app and loads the file instead. A backup is saved first.")
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
            let summary = try ImportService.replaceAll(data: data, context: modelContext)
            var text = "Imported \(summary.customers) customers and \(summary.visits) visits."
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
}

#Preview {
    SettingsView()
        .modelContainer(for: Customer.self, inMemory: true)
}
