import SwiftUI
import SwiftData

/// The working screen: who's next, day by day (Docs/SPEC.md sections 3 and 4.6).
struct NextUpView: View {
    @Query private var customers: [Customer]
    @Query private var visits: [Visit]
    @Query private var crews: [Crew]
    @Query private var workDays: [WorkDay]
    @Query private var settings: [AppSettings]
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(UndoCenter.self) private var undoCenter
    @Environment(RoundClock.self) private var clock

    /// A skip waiting for "they still owe money" confirmation.
    @State private var skipAsk: Customer?
    /// A "Paid" swipe for someone who already owes: asks about the older cleans.
    @State private var paidRequest: PaidRequest?

    /// Compact width (iPhone): tapping a customer opens a sheet.
    @State private var selected: Customer?
    /// Regular width (iPad): the list on the left, the logging panel for this customer on the right.
    @State private var selectedID: UUID?
    /// The day whose customers are being messaged.
    @State private var messageDay: RoundPlanner.DayPlan?
    /// The customer whose group is being changed (from the row's menu).
    @State private var grouping: Customer?
    /// Today's done customers are folded into one row unless this is on.
    @State private var showDone = false

    var body: some View {
        let perfStart = PerfProbe.now()
        let today = clock.today
        let _ = VisitLookup.begin(visits)
        let plan = RoundPlanner.plan(customers: customers, settings: settings.first, crews: crews, workDays: workDays, today: today)
        let _ = VisitLookup.end()
        let _ = PerfProbe.end("Round", perfStart)

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
        List(selection: sizeClass == .regular ? $selectedID : .constant(nil)) {
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
                    let done = day.rows.filter(\.isDone)
                    if day.date == today && !done.isEmpty {
                        doneSummary(done, total: day.doneTotal)
                        // One list with stable identities, so a row that becomes done never hands its open swipe to
                        // whichever row slides into its place.
                        ForEach(showDone ? day.rows : day.rows.filter { !$0.isDone }) { dayRow in
                            row(for: dayRow, on: day.date, today: today)
                        }
                    } else {
                        ForEach(day.rows) { dayRow in row(for: dayRow, on: day.date, today: today) }
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
        .contentMargins(.top, 0, for: .scrollContent)
        .sheet(item: $messageDay) { MessageDayView(day: $0) }
        .sheet(item: $grouping) { GroupPickerView(customer: $0) }
        .owedOnPaidPrompt($paidRequest)
        .alert("Skip anyway?", isPresented: Binding(get: { skipAsk != nil }, set: { if !$0 { skipAsk = nil } }), presenting: skipAsk) { person in
            if OwedReminder.canSend(to: person) {
                Button("Skip and send a reminder") { OwedReminder.open(for: person); perform(.skipped, for: person) }
            }
            Button("Skip anyway", role: .destructive) { perform(.skipped, for: person) }
            Button("Go back", role: .cancel) {}
        } message: { person in
            let owed = RoundMetrics.moneyOwed([person])
            Text("\(person.name) still owes \(owed.amount.formatted(.currency(code: "GBP"))) from \(owed.cleans) earlier clean\(owed.cleans == 1 ? "" : "s").")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.bar, for: .navigationBar)
    }

    /// One row standing in for everyone done today, so the next customer is always at the top.
    private func doneSummary(_ done: [RoundPlanner.DayRow], total: Decimal) -> some View {
        let cleaned = done.filter { $0.state == .cleanedToday }.count
        let other = done.count - cleaned
        return Button { withAnimation { showDone.toggle() } } label: {
            HStack {
                Label {
                    Text("Done today: \(cleaned) cleaned · \(total.pounds)" + (other > 0 ? " · \(other) skipped or not due" : ""))
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: showDone ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func row(for dayRow: RoundPlanner.DayRow, on date: Date, today: Date) -> some View {
        let customer = dayRow.customer
        Group {
            if sizeClass == .regular {
                NextUpRow(customer: customer, state: dayRow.state).tag(customer.id)
            } else {
                Button { selected = customer } label: {
                    NextUpRow(customer: customer, state: dayRow.state)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .leading) {
            // Neighbours kept together on the same day: a bar down the side, alternating colours between clusters.
            if dayRow.inCluster {
                Capsule()
                    .fill((dayRow.group ?? 0).isMultiple(of: 2) ? Color.blue.opacity(0.55) : Color.teal.opacity(0.7))
                    .frame(width: 4)
                    .padding(.vertical, 2)
                    .offset(x: -12)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !dayRow.isDone {
                Button { log(.cleanedPaid, for: customer) } label: { Label("Paid", systemImage: "checkmark.circle.fill") }
                    .tint(.green)
                Button { log(.cleanedNotPaid, for: customer) } label: { Label("Not paid", systemImage: "clock.badge.exclamationmark") }
                    .tint(.orange)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !dayRow.isDone {
                Button { log(.skipped, for: customer) } label: { Label("Skipped", systemImage: "forward.circle") }
                    .tint(.red)
                if date > today && !dayRow.isPending {
                    // Pull a later day's customer into today's work (books them for today).
                    Button { withAnimation { customer.bookedFor = today } } label: { Label("Do today", systemImage: "arrow.up.to.line") }
                        .tint(.purple)
                }
            }
        }
        .contextMenu {
            if date > today && !dayRow.isDone && !dayRow.isPending {
                Button { withAnimation { customer.bookedFor = today } } label: { Label("Do today", systemImage: "arrow.up.to.line") }
            }
            Button { grouping = customer } label: { Label("Change group...", systemImage: "square.stack.3d.up") }
            if customer.bookedFor != nil {
                Button(role: .destructive) { withAnimation { customer.bookedFor = nil } } label: { Label("Remove booking", systemImage: "xmark.circle") }
            }
        }
    }

    private func log(_ action: VisitLogger.Action, for customer: Customer) {
        if case .skipped = action, RoundMetrics.moneyOwed([customer]).cleans > 0 {
            skipAsk = customer
            return
        }
        if case .cleanedPaid = action, RoundMetrics.moneyOwed([customer]).cleans > 0 {
            paidRequest = PaidRequest(customer: customer)
            return
        }
        perform(action, for: customer)
    }

    private func perform(_ action: VisitLogger.Action, for customer: Customer) {
        let context = modelContext
        let undoCenter = undoCenter
        VisitLogger.afterAnimation {
            let undo = VisitLogger.perform(action, for: customer, in: context)
            undoCenter.offer("\(customer.name): \(action.summary)", undo: undo)
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

    /// "Howie + Dad · £144 done · £296 left · 3 booked" today; "Howie + Dad · 26 houses · £448 of £440" otherwise.
    private var summary: String {
        var parts = [day.crewName]
        if isToday && day.doneTotal > 0 {
            parts.append("\(day.doneTotal.pounds) done")
            parts.append("\(day.total.pounds) left")
        } else {
            parts.append("\(day.customers.count) houses")
            parts.append("\(day.total.pounds) of \(day.bookTo.pounds)")
        }
        if day.bookedCount > 0 { parts.append("\(day.bookedCount) booked") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 2) {
            Text((isToday ? "Today, " : "") + RoundCalendar.weekdayShort(day.date))
                .font(.headline)
                .foregroundStyle(.primary)
            Text(summary)
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
    var state: NextUp.State = .planned

    private var isDimmed: Bool { state != .planned && state != .booked }

    private var owed: (amount: Decimal, cleans: Int) { RoundMetrics.moneyOwed([customer]) }

    var body: some View {
        let owed = owed
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(customer.name).font(.headline)
                    switch state {
                    case .notStarted: tag("Not started · tap to start")
                    case .everyOtherOff: tag("EO · not this round", colour: .gray)
                    case .booked: tag("Booked", colour: .purple)
                    case .skippedToday: tag("Skipped today", colour: .red)
                    case .notDueToday: tag("Not due", colour: .gray)
                    default: EmptyView()
                    }
                    if customer.everyOther && state != .everyOtherOff { tag("EO") }
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
                if state == .cleanedToday {
                    Label(chargedToday.pounds, systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    Text(customer.price.pounds)
                        .font(.headline)
                }
                Image(systemName: customer.contact == .ring ? "phone" : "message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(isDimmed ? 0.45 : 1)
        .contentShape(Rectangle())
    }

    /// What was charged for today's clean(s).
    private var chargedToday: Decimal {
        let today = RoundCalendar.startOfDay()
        return customer.allVisits.filter { $0.kind == .cleaned && $0.date == today }.reduce(0) { $0 + $1.charged }
    }

    private func tag(_ text: String, colour: Color = .blue) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(colour.opacity(0.15), in: Capsule())
            .foregroundStyle(colour)
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

            if let booked = customer.bookedFor {
                Section {
                    LabeledContent("Booked for", value: RoundCalendar.weekdayShort(booked))
                    Button("Remove booking", role: .destructive) { customer.bookedFor = nil }
                } footer: {
                    Text("They were messaged for this day, so the round keeps them on it. Logging a clean or skip clears it.")
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
