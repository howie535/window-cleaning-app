import SwiftUI
import SwiftData

/// Business expenses for a tax year: added up by month and by category. The year's total feeds the Tax Year page;
/// every expense is kept, and the detail can be shared as a CSV if HMRC ask.
struct ExpensesView: View {
    @Environment(RoundClock.self) private var clock
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    /// nil = the current tax year.
    @State var chosenYear: Int?
    @State private var editing: Expense?
    @State private var isAdding = false
    @State private var exportURL: URL?

    var body: some View {
        let current = TaxYear.startYear(containing: clock.today)
        let year = chosenYear ?? current
        let years = Array(Set(expenses.map { TaxYear.startYear(containing: $0.date) } + [current])).sorted()
        let range = TaxYear.range(startYear: year)
        let inYear = expenses.filter { range.contains($0.date) }
        let total = inYear.reduce(Decimal(0)) { $0 + $1.amount }
        let byMonth = Dictionary(grouping: inYear) { RoundCalendar.london.dateInterval(of: .month, for: $0.date)!.start }
            .sorted { $0.key > $1.key }
        let byCategory = Dictionary(grouping: inYear, by: \.category)
            .map { (category: $0.key, total: $0.value.reduce(Decimal(0)) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }

        List {
            Section {
                Picker("Tax year", selection: Binding(get: { year }, set: { chosenYear = $0; exportURL = nil })) {
                    ForEach(years, id: \.self) { Text(TaxYear.label(startYear: $0)).tag($0) }
                }
                LabeledContent("Total expenses") { Text(total.pounds).font(.headline).monospacedDigit() }
            }
            if !byCategory.isEmpty {
                Section("By category") {
                    ForEach(byCategory, id: \.category) { row in
                        LabeledContent(row.category.isEmpty ? "Uncategorised" : row.category) {
                            Text(row.total.pounds).monospacedDigit()
                        }
                    }
                }
            }
            if inYear.isEmpty {
                Section { Text("No expenses this tax year.").foregroundStyle(.secondary) }
            }
            ForEach(byMonth, id: \.key) { month, items in
                Section {
                    ForEach(items) { expense in
                        Button { editing = expense } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(expense.category.isEmpty ? "Expense" : expense.category).foregroundStyle(.primary)
                                    Text(RoundCalendar.shortWithYear(expense.date) + (expense.note.isEmpty ? "" : " · \(expense.note)"))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(expense.amount.pounds).foregroundStyle(.primary).monospacedDigit()
                            }
                        }
                        .tint(.primary)
                    }
                    .onDelete { offsets in
                        for index in offsets { modelContext.delete(items[index]) }
                        try? modelContext.save()
                    }
                } header: {
                    HStack {
                        Text(month.formatted(.dateTime.month(.wide).year()))
                        Spacer()
                        Text(items.reduce(Decimal(0)) { $0 + $1.amount }.pounds).monospacedDigit()
                    }
                }
            }
            if !inYear.isEmpty {
                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Share expenses CSV", systemImage: "square.and.arrow.up") }
                    } else {
                        Button("Prepare expenses CSV") { exportURL = try? Self.writeCSV(year: year, expenses: inYear) }
                    }
                } footer: {
                    Text("Every expense with its date, category and note, for HMRC if asked.")
                }
            }
        }
        .navigationTitle("Expenses")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: { Label("Add expense", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $isAdding, onDismiss: { exportURL = nil }) { ExpenseEditor(expense: nil, categories: categories) }
        .sheet(item: $editing, onDismiss: { exportURL = nil }) { ExpenseEditor(expense: $0, categories: categories) }
    }

    /// The standard list plus any other category already used.
    private var categories: [String] {
        let used = Set(expenses.map(\.category).filter { !$0.isEmpty })
        return Expense.standardCategories + used.subtracting(Expense.standardCategories).sorted()
    }

    static func writeCSV(year: Int, expenses: [Expense]) throws -> URL {
        func field(_ text: String) -> String {
            text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
        }
        var lines = ["Expenses, tax year \(TaxYear.label(startYear: year))", "", "Date,Category,Amount,Note"]
        for e in expenses.sorted(by: { $0.date < $1.date }) {
            lines.append("\(RoundCalendar.dayString(e.date)),\(field(e.category)),\(NSDecimalNumber(decimal: e.amount).stringValue),\(field(e.note))")
        }
        lines.append("Total,,\(NSDecimalNumber(decimal: expenses.reduce(Decimal(0)) { $0 + $1.amount }).stringValue),")
        let url = URL.temporaryDirectory.appendingPathComponent("splash-out-expenses-\(TaxYear.label(startYear: year)).csv")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

/// Add or change one expense.
private struct ExpenseEditor: View {
    let expense: Expense?
    let categories: [String]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var amountText = ""
    @State private var category = ""
    @State private var note = ""
    @State private var loaded = false

    private var amount: Decimal? { Decimal(string: amountText).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                LabeledField(label: "Amount (£)") {
                    TextField("0.00", text: $amountText).keyboardType(.decimalPad)
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                PickOrTypeField(label: "Category", value: $category, options: categories, placeholder: "e.g. Fuel")
                LabeledField(label: "Note (optional)") {
                    TextField("e.g. Ladder from Screwfix", text: $note)
                }
                if let expense {
                    Button("Delete expense", role: .destructive) {
                        modelContext.delete(expense)
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .navigationTitle(expense == nil ? "New Expense" : "Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(amount == nil) }
            }
            .keyboardDoneButton()
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let expense {
                    date = expense.date
                    amountText = NSDecimalNumber(decimal: expense.amount).stringValue
                    category = expense.category
                    note = expense.note
                }
            }
        }
    }

    private func save() {
        guard let amount else { return }
        let day = RoundCalendar.london.startOfDay(for: date)
        let cleanCategory = category.trimmingCharacters(in: .whitespaces)
        let cleanNote = note.trimmingCharacters(in: .whitespaces)
        if let expense {
            expense.date = day; expense.amount = amount; expense.category = cleanCategory; expense.note = cleanNote
        } else {
            modelContext.insert(Expense(date: day, amount: amount, category: cleanCategory, note: cleanNote))
        }
        try? modelContext.save()
        dismiss()
    }
}
