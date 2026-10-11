import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Share-sheet exports: customer list, tax-year income list and an analysis report (Docs/NEXT_STEPS.md).
struct ExportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var customers: [Customer]

    @State private var taxYear = TaxYear.startYear(containing: Date())
    @State private var ledgerNames = true
    @State private var analysisNames = true
    @State private var analysisNotes = true

    private var years: [Int] {
        let current = TaxYear.startYear(containing: Date())
        let first = customers.flatMap(\.allVisits).map(\.date).min().map(TaxYear.startYear(containing:)) ?? current
        return Array(first...current).reversed()
    }

    var body: some View {
        List {
            Section {
                ExportRow(title: "Customer list (CSV)", prepare: { try DataExports.customersCSV(context: modelContext) })
            } header: {
                Text("Customers")
            } footer: {
                Text("Every customer with their address, phone, price, round, area, status and notes. Opens in Numbers or Excel. The same columns can be brought back in with Import on the Customers screen.")
            }

            Section {
                Picker("Tax year", selection: $taxYear) {
                    ForEach(years, id: \.self) { Text(TaxYear.label(startYear: $0)).tag($0) }
                }
                Toggle("Include customer names and addresses", isOn: $ledgerNames)
                ExportRow(title: "Income list (CSV)", prepare: {
                    try DataExports.incomeListCSV(taxYear: taxYear, includeNames: ledgerNames, context: modelContext)
                })
                .id("\(taxYear)-\(ledgerNames)")
            } header: {
                Text("Tax year")
            } footer: {
                Text("One line for every clean in the tax year: date, what was charged, what was paid and when it was paid, with totals at the bottom. For the month-by-month summary, use Tax Year under Reports. Tips are never counted as income.")
            }

            Section {
                Toggle("Include customer names and addresses", isOn: $analysisNames)
                Toggle("Include customer notes", isOn: $analysisNotes)
                ExportRow(title: "Analysis report (Markdown)", prepare: {
                    try DataExports.analysisReport(includeNames: analysisNames, includeNotes: analysisNotes, context: modelContext)
                })
                .id("\(analysisNames)-\(analysisNotes)")
            } header: {
                Text("For analysis")
            } footer: {
                Text("One file with the weekly, monthly and round figures, every customer and every visit, written so you can drop it into Claude and ask questions. Names, addresses and notes (gate codes and so on) are in it by default: switch them off first if you'd rather share it anonymously. Customers then appear as IDs like C001.")
            }

            Section {
                Text("To back up everything, or move to a new phone, use Export backup in Settings.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Exports")
    }
}

/// "Prepare" builds the file, then it turns into a share button.
private struct ExportRow: View {
    let title: String
    let prepare: () throws -> URL

    @State private var url: URL?
    @State private var failure: String?

    var body: some View {
        Group {
            if let url {
                ShareLink(item: url) {
                    Label("Share \(title)", systemImage: "square.and.arrow.up")
                }
            } else {
                Button {
                    do { url = try prepare() } catch { failure = error.localizedDescription }
                } label: {
                    Label("Prepare \(title)", systemImage: "doc.badge.gearshape")
                }
            }
        }
        .alert("Couldn't prepare the file", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }
}

/// A gentle nudge on the Stats screen when no backup copy has been saved somewhere other than this phone for over a week.
struct BackupReminder: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var customers: [Customer]
    @AppStorage(AutoBackup.exportedKey) private var lastExported = 0.0
    @AppStorage("export.snoozeUntil") private var snoozeUntil = 0.0

    @State private var document = RoundBackupDocument(data: Data())
    @State private var isExporting = false
    @State private var failure: String?

    private var due: Bool {
        let now = Date().timeIntervalSince1970
        return !customers.isEmpty && now > snoozeUntil && (lastExported == 0 || now - lastExported > 7 * 86_400)
    }

    private var message: String {
        guard lastExported > 0 else { return "You haven't saved a backup anywhere but this phone yet." }
        let days = Int((Date().timeIntervalSince1970 - lastExported) / 86_400)
        return "Your last backup copy off this phone was \(days) days ago."
    }

    var body: some View {
        if due {
            VStack(alignment: .leading, spacing: 8) {
                Label("Back up your round", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(message + " Save one to OneDrive or iCloud Drive so it survives a lost phone.")
                    .font(.subheadline)
                HStack {
                    Button("Back up now") {
                        do {
                            document = RoundBackupDocument(data: try ExportService.data(from: modelContext))
                            isExporting = true
                        } catch { failure = error.localizedDescription }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Remind me tomorrow") { snoozeUntil = Date().timeIntervalSince1970 + 86_400 }
                        .buttonStyle(.bordered)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
            .fileExporter(isPresented: $isExporting, document: document, contentType: .json,
                          defaultFilename: "splash-out-backup-\(RoundCalendar.fileStamp())") { result in
                switch result {
                case .success: lastExported = Date().timeIntervalSince1970
                case .failure(let error): failure = error.localizedDescription
                }
            }
            .alert("Couldn't back up", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(failure ?? "") }
        }
    }
}
