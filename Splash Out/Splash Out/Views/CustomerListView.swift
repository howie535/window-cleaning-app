import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CustomerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(UndoCenter.self) private var undoCenter
    @Query(sort: \Customer.sequence) private var customers: [Customer]

    @State private var isShowingAddCustomer = false
    @State private var isShowingFileImporter = false
    @State private var pendingImport: PendingImport?
    @State private var importErrorMessage: String?

    private struct PendingImport: Identifiable {
        let id = UUID()
        let headers: [String]
        let rows: [[String]]
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(customers) { customer in
                    NavigationLink(value: customer) {
                        CustomerRow(customer: customer)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { log(.cleanedPaid, for: customer) } label: {
                            Label("Paid", systemImage: "checkmark.circle.fill")
                        }
                        .tint(.green)
                        Button { log(.cleanedNotPaid, for: customer) } label: {
                            Label("Not paid", systemImage: "clock.badge.exclamationmark")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { log(.skipped, for: customer) } label: {
                            Label("Skipped", systemImage: "forward.circle")
                        }
                        .tint(.red)
                    }
                }
            }
            .navigationTitle("Customers")
            .navigationDestination(for: Customer.self) { customer in
                CustomerDetailView(customer: customer)
            }
            .overlay {
                if customers.isEmpty {
                    ContentUnavailableView {
                        Label("No Customers Yet", systemImage: "person.crop.circle.badge.plus")
                    } description: {
                        Text("Add your first customer to get started.")
                    } actions: {
                        Button("Add Customer") {
                            isShowingAddCustomer = true
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Import from Spreadsheet") {
                            isShowingFileImporter = true
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingAddCustomer = true
                    } label: {
                        Label("Add Customer", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingFileImporter = true
                    } label: {
                        Label("Import from Spreadsheet", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddCustomer) {
                AddEditCustomerView(customer: nil)
            }
            .sheet(item: $pendingImport) { pending in
                ImportCustomersView(headers: pending.headers, rows: pending.rows)
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                onCompletion: handleFileImport
            )
            .alert("Couldn't Import File", isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrorMessage ?? "")
            }
        }
    }

    private func log(_ action: VisitLogger.Action, for customer: Customer) {
        let undo = VisitLogger.perform(action, for: customer, in: modelContext)
        undoCenter.offer("\(customer.name): \(action.summary)", undo: undo)
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure:
            importErrorMessage = "Couldn't open that file. Try picking it again."
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                importErrorMessage = "Couldn't access that file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
                importErrorMessage = "Couldn't read that file as text. Make sure it's a CSV export."
                return
            }

            let parsed = CSVParser.parse(text)
            guard let firstRow = parsed.first, !parsed.isEmpty else {
                importErrorMessage = "That file appears to be empty."
                return
            }

            pendingImport = PendingImport(headers: firstRow, rows: Array(parsed.dropFirst()))
        }
    }
}

private struct CustomerRow: View {
    let customer: Customer

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(customer.name)
                    .font(.headline)
                Text(customer.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if customer.status != .active {
                Text(customer.status.label)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.15))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            } else if !customer.area.isEmpty {
                Text(customer.area)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    CustomerListView()
        .modelContainer(for: Customer.self, inMemory: true)
}
