import SwiftUI
import SwiftData

/// The two logging options that open a form. The screen showing the quick actions owns the sheet
/// (see `visitLogSheets`), not the rows: a sheet attached to each row of a list fights with its neighbours
/// and closes straight after opening.
enum VisitSheet: Identifiable {
    case extra, custom

    var id: Int { self == .extra ? 0 : 1 }
}

extension View {
    /// Put this on the List (or other screen) that contains `VisitQuickActions`.
    func visitLogSheets(customer: Customer, selection: Binding<VisitSheet?>, onLogged: @escaping () -> Void = {}) -> some View {
        sheet(item: selection) { kind in
            switch kind {
            case .extra: ExtraCleanSheet(customer: customer, onSaved: onLogged)
            case .custom: AddCleanLogView(customer: customer)
            }
        }
    }
}

/// The one-tap options for logging a customer (Docs/SPEC.md section 3). Big rows for wet hands.
/// Meant to sit inside a List section.
struct VisitQuickActions: View {
    let customer: Customer
    /// Called after an action is logged, e.g. so a sheet can close itself.
    var onLogged: () -> Void = {}
    /// Set when "Cleaned + extra" or "Other date or amount" is tapped; the screen shows the form.
    @Binding var sheet: VisitSheet?

    @Environment(\.modelContext) private var modelContext
    @Environment(UndoCenter.self) private var undoCenter

    @State private var isConfirmingSkip = false
    /// Two-price customers: which button asked for the price (true = paid).
    @State private var choosingPriceFor: Bool?
    /// "Cleaned & paid" for someone who already owes: asks about the older cleans.
    @State private var paidRequest: PaidRequest?

    private var owed: (amount: Decimal, cleans: Int) { RoundMetrics.moneyOwed([customer]) }

    var body: some View {
        Group {
            row("Cleaned & paid", systemImage: "checkmark.circle.fill", tint: .green) {
                if customer.secondPrice != nil { choosingPriceFor = true } else { paid(.cleanedPaid) }
            }
            .owedOnPaidPrompt($paidRequest, onLogged: onLogged)
            row("Cleaned, not paid", systemImage: "clock.badge.exclamationmark", tint: .orange) {
                if customer.secondPrice != nil { choosingPriceFor = false } else { run(.cleanedNotPaid) }
            }
            .confirmationDialog("Which price?", isPresented: Binding(get: { choosingPriceFor != nil }, set: { if !$0 { choosingPriceFor = nil } }), titleVisibility: .visible) {
                if let paid = choosingPriceFor, let second = customer.secondPrice {
                    // The one not used last time comes first.
                    let options: [(String, Decimal)] = [("Usual", customer.price), (customer.secondPriceName, second)]
                    ForEach(customer.nextListPrice == second ? options.reversed() : options, id: \.0) { option in
                        Button("\(option.0) \(option.1.pounds)") {
                            let action = VisitLogger.Action.cleanedAt(price: option.1, paid: paid)
                            if paid { self.paid(action) } else { run(action) }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(customer.name) has two prices. The one not used last time is first.")
            }
            row("Cleaned + extra...", systemImage: "plus.circle", tint: .blue) {
                sheet = .extra
            }
            row("Skipped", systemImage: "forward.circle", tint: .red) {
                if owed.cleans > 0 { isConfirmingSkip = true } else { run(.skipped) }
            }
            .alert("\(customer.name) owes money", isPresented: $isConfirmingSkip) {
                Button("Skip anyway", role: .destructive) { run(.skipped) }
                Button("Go back", role: .cancel) {}
            } message: {
                Text("They still owe \(owed.amount.formatted(.currency(code: "GBP"))) from \(owed.cleans) earlier clean\(owed.cleans == 1 ? "" : "s"). Skip them anyway?")
            }
            if customer.everyOther {
                row("Not due (every other)", systemImage: "arrow.triangle.2.circlepath", tint: .gray) {
                    run(.notDue)
                }
            }
            row("Other date or amount...", systemImage: "slider.horizontal.3", tint: .secondary) {
                sheet = .custom
            }
        }
    }

    private func row(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(title)
                    .font(.title3)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .font(.title2)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A paid clean: asks about older unpaid cleans first, if there are any.
    private func paid(_ action: VisitLogger.Action) {
        if owed.cleans > 0 { paidRequest = PaidRequest(customer: customer, action: action) } else { run(action) }
    }

    private func run(_ action: VisitLogger.Action) {
        let undo = VisitLogger.perform(action, for: customer, in: modelContext)
        undoCenter.offer("\(customer.name): \(action.summary)", undo: undo)
        onLogged()
    }
}

/// "Cleaned + extra": asks for the extra amount (negative for less, e.g. front only) and a note.
struct ExtraCleanSheet: View {
    let customer: Customer
    var onSaved: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(UndoCenter.self) private var undoCenter

    @State private var extraText = ""
    @State private var note = ""
    @State private var isPaid = true

    private var extra: Decimal? { Decimal(string: extraText) }

    private var total: Decimal {
        customer.suggestedNextPrice + (extra ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Usual price", value: customer.suggestedNextPrice, format: .currency(code: "GBP"))
                    LabeledField(label: "Extra (£, use - for less)") {
                        TextField("0.00", text: $extraText)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    LabeledContent("Total", value: total, format: .currency(code: "GBP"))
                        .font(.headline)
                }
                Section {
                    LabeledField(label: "What was it for?") {
                        TextField("e.g. conservatory roof, gutters", text: $note, axis: .vertical)
                    }
                    Toggle("Paid", isOn: $isPaid)
                }
            }
            .navigationTitle("Cleaned + extra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(extra == nil)
                }
            }
        }
    }

    private func save() {
        guard let extra else { return }
        let action = VisitLogger.Action.cleanedExtra(extra: extra, note: note, paid: isPaid)
        let undo = VisitLogger.perform(action, for: customer, in: modelContext)
        undoCenter.offer("\(customer.name): \(action.summary)", undo: undo)
        dismiss()
        onSaved()
    }
}

/// A paid clean waiting for the "did they pay what they owe too?" answer.
struct PaidRequest: Identifiable {
    let customer: Customer
    var action: VisitLogger.Action = .cleanedPaid
    var id: UUID { customer.id }
}

extension View {
    /// Asks whether a customer who owes for earlier cleans paid those too, then logs the clean (and the payment).
    func owedOnPaidPrompt(_ request: Binding<PaidRequest?>, onLogged: @escaping () -> Void = {}) -> some View {
        modifier(OwedOnPaidPrompt(request: request, onLogged: onLogged))
    }
}

private struct OwedOnPaidPrompt: ViewModifier {
    @Binding var request: PaidRequest?
    var onLogged: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(UndoCenter.self) private var undoCenter
    @State private var paying: Customer?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Did they pay what they owe too?",
                                isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }),
                                titleVisibility: .visible, presenting: request) { req in
                let owed = RoundMetrics.moneyOwed([req.customer])
                Button("Yes, all \(owed.amount.pounds) as well") { payAll(req) }
                Button("Just today's clean") { logOnly(req); onLogged() }
                Button("Some of it...") { logOnly(req); paying = req.customer }
                Button("Cancel", role: .cancel) {}
            } message: { req in
                let owed = RoundMetrics.moneyOwed([req.customer])
                Text("\(req.customer.name) owes \(owed.amount.pounds) from \(owed.cleans) earlier clean\(owed.cleans == 1 ? "" : "s").")
            }
            .sheet(item: $paying) { RecordPaymentView(customer: $0) }
    }

    private func logOnly(_ req: PaidRequest) {
        let undo = VisitLogger.perform(req.action, for: req.customer, in: modelContext)
        undoCenter.offer("\(req.customer.name): \(req.action.summary)", undo: undo)
    }

    private func payAll(_ req: PaidRequest) {
        let result = VisitLogger.cleanAndPayOff(req.action, for: req.customer, in: modelContext)
        undoCenter.offer("\(req.customer.name): cleaned and paid, plus \(result.paidOff.pounds) owed", undo: result.undo)
        onLogged()
    }
}
