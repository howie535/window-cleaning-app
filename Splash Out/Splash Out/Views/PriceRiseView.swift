import SwiftUI
import SwiftData

/// Every active customer with their price after the rise (Docs/SPEC.md 4.10).
/// With no rise date set in Settings this is a preview of the next 6 April.
struct PriceRiseView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var customers: [Customer]
    @Query private var crews: [Crew]
    @Query private var workDays: [WorkDay]
    @Query private var settings: [AppSettings]

    enum Filter: String, CaseIterable { case preview = "Preview", due = "Rise due" }
    @State private var filter: Filter = .preview
    @State private var isConfirmingApply = false
    @State private var message: String?

    private func pounds(_ value: Decimal, pence: Bool = false) -> String {
        value.formatted(.currency(code: "GBP").precision(.fractionLength(pence ? 2 : 0)))
    }

    var body: some View {
        let today = RoundCalendar.startOfDay()
        let stats = RoundStats(customers: customers, settings: settings.first, crews: crews, workDays: workDays, today: today)
        let rise = stats.riseDateInUse
        let rows = stats.risePreview()
        let extra = rows.reduce(Decimal(0)) { $0 + $1.extraPerCycle }
        let roundValue = RoundMetrics.roundValue(customers)
        let dueIDs = Set(stats.risesDue().map(\.id))
        let shown = filter == .due ? rows.filter { dueIDs.contains($0.id) } : rows
        let ready = rows.filter { !rise.isPreview && ($0.effective.map { $0 <= today } ?? false) && $0.newPrice != $0.customer.price }

        List {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                LabeledContent(rise.isPreview ? "Preview date" : "Rise date", value: RoundCalendar.shortWithYear(rise.date))
                LabeledContent("Rise", value: (settings.first?.priceRisePercent ?? 0.1).formatted(.percent))
                LabeledContent("Extra per cycle (EO at half)") {
                    Text(pounds(extra)).font(.headline)
                }
                LabeledContent("Of round value", value: roundValue > 0 ? (NSDecimalNumber(decimal: extra / roundValue).doubleValue).formatted(.percent.precision(.fractionLength(1))) : "-")
                LabeledContent("Rises due", value: "\(dueIDs.count) customers")
            } footer: {
                Text(rise.isPreview
                     ? "Preview only: no rise date is set in Settings. Showing a rise on \(RoundCalendar.shortWithYear(rise.date))."
                     : "Customers whose price changed less than \(settings.first?.priceRiseDelayMonths ?? 12) months before the rise wait until 12 months after their own.")
            }

            if !rise.isPreview {
                Section {
                    Button {
                        isConfirmingApply = true
                    } label: {
                        Label("Apply \(ready.count) rises that have taken effect", systemImage: "arrow.up.circle")
                    }
                    .disabled(ready.isEmpty)
                } footer: {
                    Text("Updates each price, records it in their price history, and leaves past visits alone. A backup is saved first.")
                }
            }

            Section("\(shown.count) customers") {
                ForEach(shown) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(row.customer.name).font(.headline)
                            if row.customer.everyOther { Text("EO").font(.caption2.bold()).foregroundStyle(.blue) }
                            Spacer()
                            Text("\(pounds(row.customer.price)) to \(pounds(row.newPrice))")
                                .font(.headline)
                        }
                        Text(detail(row))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Price Rise")
        .alert("Apply price rises?", isPresented: $isConfirmingApply) {
            Button("Apply") { apply(ready, today: today) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This changes \(ready.count) customers' prices.")
        }
        .alert("Price Rise", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func detail(_ row: RoundStats.RiseRow) -> String {
        var parts = [row.customer.area].filter { !$0.isEmpty }
        if let since = row.customer.priceSince { parts.append("price since \(RoundCalendar.shortWithYear(since))") } else { parts.append("price since before records") }
        if let effective = row.effective { parts.append("rise from \(RoundCalendar.shortWithYear(effective))") } else { parts.append("no rise: price is newer") }
        if let method = row.customer.payMethod { parts.append(method.label) }
        return parts.joined(separator: " · ")
    }

    private func apply(_ rows: [RoundStats.RiseRow], today: Date) {
        _ = try? ExportService.writeBackup(from: modelContext, to: ExportService.backupDirectory)
        let changed = RoundStats.applyRises(rows, in: modelContext)
        message = "\(changed) prices updated."
    }
}
