import SwiftUI
import SwiftData

struct AddCleanLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(UndoCenter.self) private var undoCenter

    let customer: Customer

    @State private var date: Date = .now
    @State private var amountChargedText: String
    @State private var hasDifferentAmountPaid = false
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
    private var amountPaid: Decimal? {
        hasDifferentAmountPaid ? Decimal(string: amountPaidText) : amountCharged
    }

    private var isValid: Bool {
        amountCharged != nil && amountPaid != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    LabeledField(label: "Amount Charged") {
                        TextField("0.00", text: $amountChargedText)
                            .keyboardType(.decimalPad)
                    }
                }
                Section {
                    Toggle("Different amount paid", isOn: $hasDifferentAmountPaid.animation())
                    if hasDifferentAmountPaid {
                        LabeledField(label: "Amount Paid") {
                            TextField("0.00", text: $amountPaidText)
                                .keyboardType(.decimalPad)
                        }
                        paymentStatusRow
                    }
                } footer: {
                    Text("Most cleans are paid in full. Turn this on if the customer paid more or less than charged.")
                }
                Section {
                    LabeledField(label: "Notes") {
                        TextField("Reason for a different price, if any", text: $notes, axis: .vertical)
                            .lineLimit(2...5)
                    }
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
        let charged = amountCharged ?? customer.suggestedNextPrice
        let paid = amountPaid ?? charged
        let undo = VisitLogger.logCustomClean(
            for: customer,
            date: date,
            charged: charged,
            paid: paid,
            note: notes.isEmpty ? nil : notes,
            in: modelContext
        )
        undoCenter.offer("\(customer.name): clean logged", undo: undo)
        dismiss()
    }
}

#Preview {
    AddCleanLogView(customer: Customer(name: "Jane Doe", address: "1 High Street", phone: "447700900123", price: 15))
        .modelContainer(for: Customer.self, inMemory: true)
}
