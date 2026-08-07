import SwiftUI
import SwiftData

struct AddCleanLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let customer: Customer

    @State private var date: Date = .now
    @State private var amountText: String
    @State private var paid: Bool = true
    @State private var notes: String = ""

    init(customer: Customer) {
        self.customer = customer
        _amountText = State(initialValue: NSDecimalNumber(decimal: customer.price).stringValue)
    }

    private var isValid: Bool {
        Decimal(string: amountText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Amount charged", text: $amountText)
                    .keyboardType(.decimalPad)
                Toggle("Paid", isOn: $paid)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
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

    private func save() {
        let log = CleanLog(
            date: date,
            amountCharged: Decimal(string: amountText) ?? customer.price,
            paid: paid,
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
