import SwiftUI
import SwiftData
import CoreLocation

enum ImportField: String, CaseIterable, Identifiable {
    case ignore, name, firstName, lastName, address, price, phone, accessNotes, round, area, status, everyOther, frontOnly, contact, payMethod

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ignore: "Don't Import"
        case .name: "Name"
        case .firstName: "First name"
        case .lastName: "Last name"
        case .address: "Address"
        case .price: "Price"
        case .phone: "Phone"
        case .accessNotes: "Notes"
        case .round: "Round"
        case .area: "Area"
        case .status: "Status"
        case .everyOther: "Every other"
        case .frontOnly: "Front only"
        case .contact: "Contact by"
        case .payMethod: "Pays by"
        }
    }
}

struct ImportCustomersView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let headers: [String]
    let rows: [[String]]

    @State private var mapping: [Int: ImportField]
    @State private var result: ImportResult?

    private struct ImportResult {
        let imported: Int
        let skipped: Int
        let duplicates: Int
    }


    init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
        _mapping = State(initialValue: CustomerCSVImport.autoDetectedMapping(for: headers))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    ContentUnavailableView {
                        Label("Import Complete", systemImage: "checkmark.circle")
                    } description: {
                        Text(summary(of: result))
                    }
                } else {
                    mappingForm
                }
            }
            .navigationTitle("Import Customers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "Cancel" : "Done") { dismiss() }
                }
                if result == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import", action: performImport)
                            .disabled(!mapping.values.contains(.name))
                    }
                }
            }
        }
    }

    private func summary(of result: ImportResult) -> String {
        var text = "Imported \(result.imported) customers."
        if result.duplicates > 0 { text += " \(result.duplicates) already in the app, so left alone." }
        if result.skipped > 0 { text += " Skipped \(result.skipped) row\(result.skipped == 1 ? "" : "s") with no name." }
        return text
    }

    private var mappingForm: some View {
        Form {
            Section {
                Text("\(rows.count) row\(rows.count == 1 ? "" : "s") found. Match each column below to a field.")
                    .foregroundStyle(.secondary)
            }
            Section("Match Columns") {
                ForEach(headers.indices, id: \.self) { index in
                    Picker(headers[index].isEmpty ? "Column \(index + 1)" : headers[index], selection: binding(for: index)) {
                        ForEach(ImportField.allCases) { field in
                            Text(field.label).tag(field)
                        }
                    }
                }
            }
        }
    }

    private func binding(for index: Int) -> Binding<ImportField> {
        Binding(
            get: { mapping[index] ?? .ignore },
            set: { mapping[index] = $0 }
        )
    }

    private func performImport() {
        let outcome = CustomerCSVImport.run(mapping: mapping, rows: rows, context: modelContext)
        result = ImportResult(imported: outcome.imported, skipped: outcome.skipped, duplicates: outcome.duplicates)
    }
}

#Preview {
    ImportCustomersView(headers: ["Name", "Address", "Price"], rows: [["Jane Doe", "1 High Street", "15"]])
        .modelContainer(for: Customer.self, inMemory: true)
}
