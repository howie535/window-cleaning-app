import SwiftUI
import SwiftData

/// The one-tap options for logging a customer (Docs/SPEC.md section 3). Big rows for wet hands.
/// Meant to sit inside a List section.
struct VisitQuickActions: View {
    let customer: Customer
    /// Called after an action is logged, e.g. so a sheet can close itself.
    var onLogged: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(UndoCenter.self) private var undoCenter

    @State private var isShowingExtra = false
    @State private var isShowingCustom = false

    var body: some View {
        Group {
            row("Cleaned & paid", systemImage: "checkmark.circle.fill", tint: .green) {
                run(.cleanedPaid)
            }
            row("Cleaned, not paid", systemImage: "clock.badge.exclamationmark", tint: .orange) {
                run(.cleanedNotPaid)
            }
            row("Cleaned + extra...", systemImage: "plus.circle", tint: .blue) {
                isShowingExtra = true
            }
            row("Skipped", systemImage: "forward.circle", tint: .red) {
                run(.skipped)
            }
            if customer.everyOther {
                row("Not due (every other)", systemImage: "arrow.triangle.2.circlepath", tint: .gray) {
                    run(.notDue)
                }
            }
            row("Other date or amount...", systemImage: "slider.horizontal.3", tint: .secondary) {
                isShowingCustom = true
            }
        }
        .sheet(isPresented: $isShowingExtra) {
            ExtraCleanSheet(customer: customer, onSaved: onLogged)
        }
        .sheet(isPresented: $isShowingCustom) {
            AddCleanLogView(customer: customer)
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
