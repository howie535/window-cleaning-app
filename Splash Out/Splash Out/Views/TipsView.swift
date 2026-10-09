import SwiftUI
import SwiftData

/// Tips are listed here and never counted as income anywhere (Docs/SPEC.md 2).
struct TipsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tip.date, order: .reverse) private var tips: [Tip]
    @State private var isAdding = false

    var body: some View {
        List {
            Section {
                LabeledContent("Total") {
                    Text(tips.reduce(Decimal(0)) { $0 + $1.amount }, format: .currency(code: "GBP"))
                        .font(.headline)
                }
            } footer: {
                Text("Tips are never counted as income in any figure.")
            }
            Section {
                if tips.isEmpty { Text("No tips recorded.").foregroundStyle(.secondary) }
                ForEach(tips) { tip in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(tip.name.isEmpty ? "Tip" : tip.name).font(.headline)
                            Text(RoundCalendar.shortWithYear(tip.date)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(tip.amount, format: .currency(code: "GBP"))
                    }
                }
                .onDelete { offsets in
                    for index in offsets { modelContext.delete(tips[index]) }
                }
            }
        }
        .navigationTitle("Tips")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: { Label("Add tip", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $isAdding) { AddTipView() }
    }
}

private struct AddTipView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var name = ""
    @State private var amountText = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                LabeledField(label: "From") { TextField("Customer name", text: $name) }
                LabeledField(label: "Amount") { TextField("0.00", text: $amountText).keyboardType(.decimalPad) }
            }
            .navigationTitle("New tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let amount = Decimal(string: amountText), amount > 0 {
                            modelContext.insert(Tip(date: RoundCalendar.startOfDay(date), name: name, amount: amount))
                            dismiss()
                        }
                    }
                    .disabled((Decimal(string: amountText) ?? 0) <= 0)
                }
            }
        }
    }
}
