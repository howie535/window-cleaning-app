import SwiftUI
import SwiftData

struct AddCleanLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let customer: Customer

    @State private var date: Date = .now
    @State private var amountChargedText: String
    @State private var amountPaidText: String
    @State private var notes: String = ""

    init(customer: Customer, defaultAmount: Decimal? = nil) {
        self.customer = customer
        let charge = defaultAmount ?? customer.suggestedNextPrice
        let chargeText = NSDecimalNumber(decimal: charge).stringValue
        _amountChargedText = State(initialValue: chargeText)
        _amountPaidText = State(initialValue: chargeText)
    }

    private var amountCharged: Decimal? { Decimal(string: amountChargedText) }
    private var amountPaid: Decimal? { Decimal(string: amountPaidText) }

    private var isValid: Bool {
        amountCharged != nil && amountPaid != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Amount charged", text: $amountChargedText)
                        .keyboardType(.decimalPad)
                    TextField("Amount paid", text: $amountPaidText)
                        .keyboardType(.decimalPad)
                    paymentStatusRow
                }
                Section("Notes") {
                    TextField("Reason for a different price, if any", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Log a Clean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
        }
    }

    @ViewBuilder
    private var paymentStatusRow: some View {
        if let amountCharged, let amountPaid {
            let difference = amountPaid - amountCharged
            if difference == 0 {
                Label("Paid in full", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else if difference > 0 {
                Label("Overpaid by \(difference, format: .currency(code: "GBP"))", systemImage: "arrow.up.circle")
                    .foregroundStyle(.blue)
            } else {
                Label("Underpaid by \(-difference, format: .currency(code: "GBP"))", systemImage: "arrow.down.circle")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func save() {
        let log = CleanLog(
            date: date,
            amountCharged: amountCharged ?? customer.suggestedNextPrice,
            amountPaid: amountPaid ?? customer.suggestedNextPrice,
            notes: notes,
            customer: customer
        )
        modelContext.insert(log)
        dismiss()
    }
}

#Preview {
    AddCleanLogView(customer: Customer(name: "Jane Doe", address: "1 High Street", phone: "447700900123", price: 15, frequencyWeeks: 4, accessNotes: ""))
        .modelContainer(for: Customer.self, inMemory: true)
}
