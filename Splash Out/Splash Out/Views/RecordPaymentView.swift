import SwiftUI
import SwiftData

/// Mark unpaid visits paid, or enter a lump sum that pays the oldest first (Docs/SPEC.md section 3).
/// Cash, BACS and standing orders are all handled the same way.
struct RecordPaymentView: View {
    let customer: Customer

    @Environment(\.dismiss) private var dismiss
    @Environment(UndoCenter.self) private var undoCenter

    @State private var date: Date = .now
    @State private var selected: Set<PersistentIdentifier> = []
    @State private var amountText = ""
    @State private var amountEdited = false

    private var unpaid: [Visit] { VisitLogger.unpaidVisits(for: customer) }
    private var selectedVisits: [Visit] { unpaid.filter { selected.contains($0.persistentModelID) } }
    private var selectedOwed: Decimal { selectedVisits.reduce(0) { $0 + $1.charged - $1.paid } }
    private var amount: Decimal? { Decimal(string: amountText) }

    private var problem: String? {
        guard let amount, amount > 0 else { return "Enter the amount received." }
        if selectedVisits.isEmpty { return "Pick at least one clean." }
        if amount > selectedOwed {
            return "That's \((amount - selectedOwed).formatted(.currency(code: "GBP"))) more than is owed on these cleans."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cleans owed") {
                    ForEach(unpaid) { visit in
                        Button {
                            toggle(visit)
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(visit.persistentModelID) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(visit.persistentModelID) ? Color.accentColor : .secondary)
                                    .font(.title3)
                                Text(visit.date, style: .date)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(visit.charged - visit.paid, format: .currency(code: "GBP"))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    LabeledField(label: "Amount received") {
                        TextField("0.00", text: Binding(
                            get: { amountText },
                            set: { amountText = $0; amountEdited = true }
                        ))
                        .keyboardType(.decimalPad)
                    }
                    DatePicker("Date paid", selection: $date, displayedComponents: .date)
                } footer: {
                    Text(problem ?? "A lump sum pays the oldest selected cleans first.")
                        .foregroundStyle(problem == nil ? Color.secondary : Color.red)
                }
            }
            .navigationTitle("Record payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(problem != nil)
                }
            }
            .onAppear {
                selected = Set(unpaid.map(\.persistentModelID))
                syncAmount()
            }
        }
    }

    private func toggle(_ visit: Visit) {
        let id = visit.persistentModelID
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        // Ticking cleans resets the amount to what they're worth, unless it's been typed over.
        if !amountEdited { syncAmount() }
    }

    private func syncAmount() {
        amountText = NSDecimalNumber(decimal: selectedOwed).stringValue
    }

    private func save() {
        guard let amount, problem == nil else { return }
        let result = VisitLogger.recordPayment(amount, across: selectedVisits, on: date)
        undoCenter.offer("\(customer.name): payment of \(amount.formatted(.currency(code: "GBP"))) recorded", undo: result.undo)
        dismiss()
    }
}
