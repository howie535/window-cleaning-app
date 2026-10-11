import SwiftUI
import SwiftData

/// The working screen: who's next, day by day (Docs/SPEC.md sections 3 and 4.6).
struct NextUpView: View {
    @Query private var customers: [Customer]
    @Query private var crews: [Crew]
    @Query private var workDays: [WorkDay]
    @Query private var settings: [AppSettings]
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Compact width (iPhone): tapping a customer opens a sheet.
    @State private var selected: Customer?
    /// Regular width (iPad): the list on the left, the logging panel for this customer on the right.
    @State private var selectedID: UUID?
    /// The day whose customers are being messaged.
    @State private var messageDay: RoundPlanner.DayPlan?

    var body: some View {
        let today = RoundCalendar.startOfDay()
        let plan = RoundPlanner.plan(customers: customers, settings: settings.first, crews: crews, workDays: workDays, today: today)

        if sizeClass == .regular {
            NavigationSplitView {
                roundList(plan: plan, today: today)
                    .roomyRows()
                    .navigationTitle("Round")
            } detail: {
                NavigationStack {
                    if let customer = customers.first(where: { $0.id == selectedID }) {
                        CustomerLogPanel(customer: customer, onLogged: { advance(from: customer, in: plan) })
                            .id(customer.id)
                    } else {
                        ContentUnavailableView("Choose a customer", systemImage: "hand.tap",
                                               description: Text("Pick someone from the round to log their clean."))
                    }
                }
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationStack {
                roundList(plan: plan, today: today)
                    .navigationTitle("Round")
                    .sheet(item: $selected) { customer in
                        QuickLogSheet(customer: customer)
                    }
            }
        }
    }

    private func roundList(plan: RoundPlanner.Plan, today: Date) -> some View {
        List(selection: $selectedID) {
            if plan.days.isEmpty {
                ContentUnavailableView("No working days", systemImage: "calendar.badge.exclamationmark",
                                       description: Text("There are no working days coming up. Check the usual week in Settings."))
            }

            ForEach(Array(plan.days.enumerated()), id: \.element.id) { index, day in
                Section {
                    if index == 0, let pointer = plan.pointer {
                        LabeledContent("Carrying on from") { Text(pointer.name) }
                            .font(.subheadline)
                    }
                    ForEach(day.rows) { dayRow in
                        row(for: dayRow.customer, pending: dayRow.isPending)
                    }
                } header: {
                    DayHeader(day: day, isToday: day.date == today, onMessage: { messageDay = day })
                }
            }

            if !plan.later.isEmpty {
                Section("Later") {
                    Text("\(plan.later.count) more customers are due after these days.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        // Plain style keeps each day's header pinned at the top until the next day's replaces it.
        // The bar above and the header share one frosted look, so rows fade out the same way under both.
        .listStyle(.plain)
        .sheet(item: $messageDay) { MessageDayView(day: $0) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.bar, for: .navigationBar)
    }

    @ViewBuilder
    private func row(for customer: Customer, pending: Bool) -> some View {
        if sizeClass == .regular {
            NextUpRow(customer: customer, isPending: pending).tag(customer.id)
        } else {
            Button { selected = customer } label: {
                NextUpRow(customer: customer, isPending: pending)
            }
            .buttonStyle(.plain)
        }
    }

    /// After logging, move on to whoever is next in the round.
    private func advance(from customer: Customer, in plan: RoundPlanner.Plan) {
        let flat = plan.days.flatMap(\.customers)
        guard let index = flat.firstIndex(where: { $0.id == customer.id }) else { return }
        let following = flat.dropFirst(index + 1).first
        selectedID = following?.id
    }
}

private struct DayHeader: View {
    let day: RoundPlanner.DayPlan
    let isToday: Bool
    var onMessage: () -> Void = {}

    /// Customers on this day who haven't had the message, once some others have (for example someone skipped,
    /// so the next people were pulled forward).
    private var newCount: Int {
        let sent = Set(UserDefaults.standard.stringArray(forKey: DayMessage.sentKey(day.date)) ?? [])
        guard !sent.isEmpty else { return 0 }
        return day.customers.filter { $0.contact == .whatsapp && !$0.whatsAppDigits.isEmpty && !sent.contains($0.id.uuidString) }.count
    }

    var body: some View {
        HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 2) {
            Text((isToday ? "Today, " : "") + RoundCalendar.weekdayShort(day.date))
                .font(.headline)
                .foregroundStyle(.primary)
            Text("\(day.crewName) · \(day.customers.count) houses · \(day.total.pounds) of \(day.bookTo.pounds)")
                .font(.caption)
                .textCase(nil)
        }
            Spacer()
            if !day.customers.isEmpty {
                Button(action: onMessage) { Label(newCount > 0 ? "Message · \(newCount) new" : "Message", systemImage: "message") }
                    .font(.subheadline)
                    .buttonStyle(.bordered)
                    .textCase(nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .listRowInsets(EdgeInsets())
    }
}

private struct NextUpRow: View {
    let customer: Customer
    var isPending = false

    private var owed: (amount: Decimal, cleans: Int) { RoundMetrics.moneyOwed([customer]) }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(customer.name).font(.headline)
                    if isPending { tag("Not started · tap to start") }
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
                        Text("Owes \(owed.amount.pounds)")
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
                Text(customer.price.pounds)
                    .font(.headline)
                Image(systemName: customer.contact == .ring ? "phone" : "message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(isPending ? 0.45 : 1)
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

/// The one-tap logging options for a customer: shown in a sheet on iPhone and as the right-hand panel on iPad.
struct CustomerLogPanel: View {
    let customer: Customer
    var onLogged: () -> Void = {}

    @State private var logSheet: VisitSheet?

    private var owed: (amount: Decimal, cleans: Int) { RoundMetrics.moneyOwed([customer]) }

    var body: some View {
        List {
            if customer.status == .notStarted {
                Section {
                    Button { customer.status = .active } label: {
                        Label("Start \(customer.name): put them on the round", systemImage: "play.circle.fill")
                            .font(.title3)
                            .padding(.vertical, 6)
                    }
                } footer: {
                    Text("They haven't started yet, so they show greyed out and don't count towards the day's total.")
                }
            }

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
                VisitQuickActions(customer: customer, onLogged: onLogged, sheet: $logSheet)
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
        .visitLogSheets(customer: customer, selection: $logSheet, onLogged: onLogged)
    }
}

/// Tapping a customer on the round gives the one-tap options straight away.
struct QuickLogSheet: View {
    let customer: Customer

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CustomerLogPanel(customer: customer, onLogged: { dismiss() })
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }
}
