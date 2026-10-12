import SwiftUI
import SwiftData

/// Correct a visit already logged: its date, what happened, what was charged and paid, and the note. Or delete it.
struct EditVisitView: View {
    let visit: Visit

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(UndoCenter.self) private var undoCenter

    @State private var date = Date()
    @State private var kind: VisitKind = .cleaned
    @State private var chargedText = ""
    @State private var paidText = ""
    @State private var note = ""
    @State private var isConfirmingDelete = false

    private var charged: Decimal? { Decimal(string: chargedText) }
    private var paid: Decimal? { paidText.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : Decimal(string: paidText) }

    private var isValid: Bool { kind != .cleaned || (charged != nil && paid != nil) }

    private var name: String { visit.customer?.name ?? "Visit" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("What happened", selection: $kind) {
                        Text("Cleaned").tag(VisitKind.cleaned)
                        Text("Skipped").tag(VisitKind.skipped)
                        Text("Not due").tag(VisitKind.notDue)
                    }
                }
                if kind == .cleaned {
                    Section {
                        LabeledContent("List price", value: visit.listPrice, format: .currency(code: "GBP"))
                        LabeledField(label: "Charged") {
                            TextField("0.00", text: $chargedText).keyboardType(.decimalPad)
                        }
                        LabeledField(label: "Paid (0 if not paid yet)") {
                            TextField("0.00", text: $paidText).keyboardType(.decimalPad)
                        }
                    } footer: {
                        Text("Charged is what the clean counts for in the stats. Paid less than charged shows on Money Owed.")
                    }
                }
                Section {
                    LabeledField(label: "Note") {
                        TextField("Optional", text: $note, axis: .vertical).lineLimit(1...4)
                    }
                }
                Section {
                    Button("Delete this visit", role: .destructive) { isConfirmingDelete = true }
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Edit visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!isValid) }
            }
            .confirmationDialog("Delete this visit?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
            } message: {
                Text("It comes out of every total. You can undo straight after.")
            }
            .onAppear(perform: load)
        }
    }

    private func text(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }

    private func load() {
        date = visit.date
        kind = visit.kind
        chargedText = text(visit.kind == .cleaned ? visit.charged : visit.listPrice)
        paidText = visit.kind == .cleaned ? text(visit.paid) : ""
        note = visit.note ?? ""
    }

    private func save() {
        let snapshot = VisitSnapshot(visit)
        let day = RoundCalendar.startOfDay(date)
        visit.date = day
        visit.kind = kind
        if kind == .cleaned {
            let newPaid = paid ?? 0
            visit.charged = charged ?? 0
            if newPaid != visit.paid || (newPaid > 0 && visit.paidDate == nil) {
                visit.paidDate = newPaid > 0 ? (visit.paidDate ?? day) : nil
            }
            visit.paid = newPaid
        } else {
            visit.charged = 0
            visit.paid = 0
            visit.paidDate = nil
            visit.creditApplied = 0
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        visit.note = trimmed.isEmpty ? nil : trimmed
        try? modelContext.save()
        let target = visit
        undoCenter.offer("\(name): visit changed") { snapshot.restore(target) }
        dismiss()
    }

    private func delete() {
        guard let customer = visit.customer else { return }
        let snapshot = VisitSnapshot(visit)
        let context = modelContext
        VisitLogger.remove(visit, in: context)
        undoCenter.offer("\(customer.name): visit deleted") {
            let restored = snapshot.makeVisit()
            context.insert(restored)
            restored.customer = customer
            try? context.save()
        }
        dismiss()
    }
}

/// A copy of a visit's values, for undo.
struct VisitSnapshot {
    var date: Date
    var kind: VisitKind
    var listPrice: Decimal
    var charged: Decimal
    var paid: Decimal
    var paidDate: Date?
    var note: String?
    var creditApplied: Decimal

    init(_ visit: Visit) {
        date = visit.date
        kind = visit.kind
        listPrice = visit.listPrice
        charged = visit.charged
        paid = visit.paid
        paidDate = visit.paidDate
        note = visit.note
        creditApplied = visit.creditApplied
    }

    func restore(_ visit: Visit) {
        visit.date = date
        visit.kind = kind
        visit.listPrice = listPrice
        visit.charged = charged
        visit.paid = paid
        visit.paidDate = paidDate
        visit.note = note
        visit.creditApplied = creditApplied
    }

    func makeVisit() -> Visit {
        Visit(date: date, kind: kind, listPrice: listPrice, charged: charged, paid: paid, paidDate: paidDate, note: note, creditApplied: creditApplied)
    }
}
