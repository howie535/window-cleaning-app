import SwiftUI
import SwiftData
import CoreLocation

enum ImportField: String, CaseIterable, Identifiable {
    case ignore, name, address, price, phone, accessNotes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ignore: "Don't Import"
        case .name: "Name"
        case .address: "Address"
        case .price: "Price"
        case .phone: "Phone"
        case .accessNotes: "Notes"
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
    }

    init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
        _mapping = State(initialValue: Self.autoDetectedMapping(for: headers))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    ContentUnavailableView {
                        Label("Import Complete", systemImage: "checkmark.circle")
                    } description: {
                        Text(result.skipped > 0
                            ? "Imported \(result.imported) customers. Skipped \(result.skipped) row\(result.skipped == 1 ? "" : "s") with no name."
                            : "Imported \(result.imported) customers.")
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

    private static func autoDetectedMapping(for headers: [String]) -> [Int: ImportField] {
        var mapping: [Int: ImportField] = [:]
        for (index, header) in headers.enumerated() {
            let lower = header.lowercased()
            if lower.contains("name") {
                mapping[index] = .name
            } else if lower.contains("address") {
                mapping[index] = .address
            } else if lower.contains("price") || lower.contains("cost") {
                mapping[index] = .price
            } else if lower.contains("phone") {
                mapping[index] = .phone
            } else if lower.contains("note") {
                mapping[index] = .accessNotes
            }
        }
        return mapping
    }

    private var maxSequenceDescriptor: FetchDescriptor<Customer> {
        var descriptor = FetchDescriptor<Customer>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    private func performImport() {
        var imported = 0
        var skipped = 0
        var nextSequence = ((try? modelContext.fetch(maxSequenceDescriptor))?.first?.sequence ?? 0) + 1

        for row in rows {
            var name = ""
            var address = ""
            var phone = ""
            var notes = ""
            var price: Decimal = 0

            for (index, field) in mapping {
                guard index < row.count else { continue }
                let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                switch field {
                case .name: name = value
                case .address: address = value
                case .price: price = CSVParser.parsePrice(value) ?? 0
                case .phone: phone = UKPhoneNumber.toNationalFormat(value)
                case .accessNotes: notes = value
                case .ignore: break
                }
            }

            guard !name.isEmpty else {
                skipped += 1
                continue
            }

            let customer = Customer(
                name: name,
                address: address,
                phone: phone,
                price: price,
                sequence: nextSequence,
                notes: notes.isEmpty ? [] : [notes]
            )
            modelContext.insert(customer)
            imported += 1
            nextSequence += 1

            if !address.isEmpty {
                Task {
                    let coordinate = await Geocoding.coordinate(for: address)
                    customer.latitude = coordinate?.latitude
                    customer.longitude = coordinate?.longitude
                }
            }
        }

        result = ImportResult(imported: imported, skipped: skipped)
    }
}

#Preview {
    ImportCustomersView(headers: ["Name", "Address", "Price"], rows: [["Jane Doe", "1 High Street", "15"]])
        .modelContainer(for: Customer.self, inMemory: true)
}
