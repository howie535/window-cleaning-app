import SwiftUI
import SwiftData

/// The working screen: who's next, day by day (Docs/SPEC.md sections 3 and 4.6).
struct NextUpView: View {
    @Query private var customers: [Customer]
    @Query private var crews: [Crew]
    @Query private var workDays: [WorkDay]
    @Query private var settings: [AppSettings]

    @State private var selected: Customer?

    var body: some View {
        let today = RoundCalendar.startOfDay()
        let plan = RoundPlanner.plan(customers: customers, settings: settings.first, crews: crews, workDays: workDays, today: today)

        NavigationStack {
            List {
                if let pointer = plan.pointer {
                    Section {
                        LabeledContent("Carrying on from") {
                            Text(pointer.name)
                        }
                        .font(.subheadline)
                    }
                }

                if plan.days.isEmpty {
                    ContentUnavailableView("No working days", systemImage: "calendar.badge.exclamationmark",
                                           description: Text("There are no working days coming up. Check the usual week in Settings."))
                }

                ForEach(plan.days) { day in
                    Section {
                        ForEach(day.customers) { customer in
                            Button { selected = customer } label: {
                                NextUpRow(customer: customer)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        DayHeader(day: day, isToday: day.date == today)
                    }
                }

                if !plan.later.isEmpty {
                    Section("Later") {
                        Text("\(plan.later.count) more customers are due after these days.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Round")
            .sheet(item: $selected) { customer in
                QuickLogSheet(customer: customer)
            }
        }
    }
}

private struct DayHeader: View {
    let day: RoundPlanner.DayPlan
    let isToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text((isToday ? "Today, " : "") + RoundCalendar.weekdayShort(day.date))
                .font(.headline)
                .foregroundStyle(.primary)
            Text("\(day.crewName) · \(day.customers.count) houses · \(day.total.formatted(.currency(code: "GBP").precision(.fractionLength(0)))) of \(day.bookTo.formatted(.currency(code: "GBP").precision(.fractionLength(0))))")
                .font(.caption)
                .textCase(nil)
        }
    }
}

private struct NextUpRow: View {
    let customer: Customer

    private var owed: (amount: Decimal, cleans: Int) { RoundMetrics.moneyOwed([customer]) }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(customer.name).font(.headline)
                    if customer.everyOther { tag("EO") }
                    if customer.frontOnly { tag("Front only") }
                }
                Text(customer.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    if !customer.area.isEmpty { Text(customer.area) }
                    if let last = customer.lastCleanDate { Text("Last \(RoundCalendar.short(last))") }
                    if owed.cleans > 0 {
                        Text("Owes \(owed.amount.formatted(.currency(code: "GBP").precision(.fractionLength(0))))")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let note = customer.notes.first {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(customer.price, format: .currency(code: "GBP").precision(.fractionLength(0)))
                    .font(.headline)
                Image(systemName: customer.contact == .ring ? "phone" : "message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.blue.opacity(0.15), in: Capsule())
            .foregroundStyle(.blue)
    }
}

/// Tapping a customer on the round gives the one-tap options straight away.
struct QuickLogSheet: View {
    let customer: Customer

    @Environment(\.dismiss) private var dismiss

    private var owed: (amount: Decimal, cleans: Int) { RoundMetrics.moneyOwed([customer]) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(customer.address)
                    if owed.cleans > 0 {
                        LabeledContent("Owes", value: owed.amount, format: .currency(code: "GBP"))
                            .foregroundStyle(.red)
                    }
                    ForEach(customer.notes, id: \.self) { note in
                        Text(note).foregroundStyle(.orange)
                    }
                }

                Section("Log") {
                    VisitQuickActions(customer: customer, onLogged: { dismiss() })
                }

                Section {
                    ContactButton(customer: customer)
                    NavigationLink("Customer page") {
                        CustomerDetailView(customer: customer)
                    }
                }
            }
            .navigationTitle(customer.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
