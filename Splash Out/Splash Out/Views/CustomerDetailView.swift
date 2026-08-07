import SwiftUI
import SwiftData

struct CustomerDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var customer: Customer

    @State private var isShowingEdit = false
    @State private var isShowingLogClean = false

    private var sortedLogs: [CleanLog] {
        customer.cleanLogs.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Address", value: customer.address)
                LabeledContent("Phone", value: customer.phone)
                LabeledContent("Price", value: customer.price, format: .currency(code: "GBP"))
                LabeledContent("Frequency", value: "Every \(customer.frequencyWeeks) week\(customer.frequencyWeeks == 1 ? "" : "s")")
                if let nextDueDate = customer.nextDueDate {
                    LabeledContent("Next Due") {
                        Text(nextDueDate, style: .date)
                            .foregroundStyle(customer.isDue ? .orange : .primary)
                    }
                }
                if !customer.accessNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Access Notes").foregroundStyle(.secondary)
                        Text(customer.accessNotes)
                    }
                }
            }

            Section {
                Button {
                    isShowingLogClean = true
                } label: {
                    Label("Log a Clean", systemImage: "checkmark.circle")
                }
                WhatsAppButton(customer: customer)
            }

            Section("Clean History") {
                if sortedLogs.isEmpty {
                    Text("No cleans logged yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedLogs) { log in
                        CleanLogRow(log: log)
                    }
                    .onDelete(perform: deleteLogs)
                }
            }
        }
        .navigationTitle(customer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isShowingEdit = true }
            }
        }
        .sheet(isPresented: $isShowingEdit) {
            AddEditCustomerView(customer: customer)
        }
        .sheet(isPresented: $isShowingLogClean) {
            AddCleanLogView(customer: customer)
        }
    }

    private func deleteLogs(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sortedLogs[index])
        }
    }
}

private struct CleanLogRow: View {
    let log: CleanLog

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(log.date, style: .date)
                if !log.notes.isEmpty {
                    Text(log.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(log.amountCharged, format: .currency(code: "GBP"))
                Text(log.paid ? "Paid" : "Unpaid")
                    .font(.caption)
                    .foregroundStyle(log.paid ? .green : .red)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CustomerDetailView(customer: Customer(name: "Jane Doe", address: "1 High Street", phone: "447700900123", price: 15, frequencyWeeks: 4, accessNotes: "Side gate code 1234"))
    }
    .modelContainer(for: Customer.self, inMemory: true)
}
