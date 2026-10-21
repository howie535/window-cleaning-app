import SwiftUI
import SwiftData

/// Price rises (Docs/SPEC.md 4.10), in three steps:
/// 1. choose who gets a rise and at what price, 2. set them (each customer then shows "Rising to £X from ..."),
/// 3. tell customers by WhatsApp. New prices start by themselves on their date.
struct PriceRiseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RoundClock.self) private var clock
    @Query private var customers: [Customer]
    @Query private var crews: [Crew]
    @Query private var workDays: [WorkDay]
    @Query private var settings: [AppSettings]

    enum Filter: String, CaseIterable { case due = "Rise due", all = "Everyone" }
    @State private var filter: Filter = .due
    enum Mode: String, CaseIterable { case percent = "Same %", target = "To target average" }
    @State private var mode: Mode = .percent
    /// Ticks changed by hand (otherwise customers due a rise are ticked).
    @State private var ticked: [UUID: Bool] = [:]
    /// New prices typed by hand.
    @State private var custom: [UUID: Decimal] = [:]
    @State private var editing: RoundStats.RiseRow?
    @State private var editText = ""
    @State private var isConfirming = false
    @State private var isTelling = false
    @State private var message: String?

    var body: some View {
        let today = clock.today
        let stats = RoundStats(customers: customers, settings: settings.first, crews: crews, workDays: workDays, today: today)
        let rise = stats.riseDateInUse
        let rows = stats.risePreview()
        let dueIDs = Set(stats.risesDue().map(\.id))
        let targetAverage = Ideal.current(stats: stats, customers: customers, weeks: settings.first?.targetRoundWeeks ?? 5).planned?.perHouse
        let rowByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let towards = targetAverage.flatMap { target in
            PriceRise.towardsTarget(target, prices: RoundMetrics.onRound(customers).filter { $0.price > 0 }.map { c in
                (c.id, c.price, RoundMetrics.perCleanPrice(c), rowByID[c.id]?.effective != nil && c.pendingPrice == nil)
            })
        }
        let targets = mode == .target ? towards?.newPrices : nil
        let shown = filter == .due ? rows.filter { (targets?[$0.id] != nil) || (targets == nil && dueIDs.contains($0.id)) || $0.customer.pendingPrice != nil } : rows
        let chosen = rows.filter { isTicked($0, due: dueIDs, targets) }
        let extra = chosen.reduce(Decimal(0)) { $0 + (price(for: $1, targets) - $1.customer.price) * ($1.customer.everyOther ? Decimal(0.5) : 1) }
        let pending = customers.filter { $0.pendingPrice != nil }
        let notTold = pending.filter { $0.pendingPriceToldAt == nil }

        List {
            Section {
                LabeledContent(rise.isPreview ? "Rise date (next 6 April)" : "Rise date", value: RoundCalendar.shortWithYear(rise.date))
                LabeledContent("Rise", value: (settings.first?.priceRisePercent ?? 0.1).formatted(.percent))
            } footer: {
                Text("Change the date and % in Settings > Price rise. Someone whose price changed recently starts later, \(settings.first?.priceRiseDelayMonths ?? 12) months after their last change.")
            }

            if !pending.isEmpty {
                Section {
                    LabeledContent("Rises set", value: "\(pending.count)")
                    LabeledContent("Told", value: "\(pending.count - notTold.count) of \(pending.count)")
                    Button { isTelling = true } label: {
                        Label(notTold.isEmpty ? "Messages sent" : "Tell customers (\(notTold.count) not told)", systemImage: "message")
                    }
                } header: {
                    Text("Set")
                } footer: {
                    Text("New prices start by themselves on their date. Each customer's page shows their rise, where it can be changed or cancelled.")
                }
            }

            Section {
                Picker("Rise", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { ticked = [:]; custom = [:] }
                if mode == .target {
                    if let towards, let targetAverage {
                        LabeledContent("Target average", value: targetAverage.formatted(.currency(code: "GBP").precision(.fractionLength(2))))
                        LabeledContent("Everyone under", value: towards.floor.pounds + " goes up to it")
                        LabeledContent("Average after", value: towards.average.formatted(.currency(code: "GBP").precision(.fractionLength(2))))
                        if !towards.reachesTarget {
                            Text("Can't reach the target with the customers a rise applies to.").font(.caption).foregroundStyle(.orange)
                        }
                    } else {
                        Text("No target yet: set the usual week's targets in Settings.").foregroundStyle(.secondary)
                    }
                }
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Chosen", value: "\(chosen.count) customers · +\(extra.pounds) a round")
                HStack {
                    Button("Untick all") { for row in rows { ticked[row.id] = false } }
                    Spacer()
                    Button("Tick everyone due") { ticked = [:] }
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
                Button { isConfirming = true } label: {
                    Label("Set \(chosen.count) rises", systemImage: "arrow.up.circle.fill").font(.headline)
                }
                .disabled(chosen.isEmpty)
            } footer: {
                Text(mode == .target
                     ? "Cheapest first: everyone under the floor goes up to it, so the round's average price reaches the target. Tap a price to change it."
                     : "Tick who gets a rise. Tap a price to change it. Customers due a rise (no change for \((settings.first?.priceRiseDueAfterMonths ?? 24) / 12) years, or no date recorded) start ticked.")
            }

            Section("\(shown.count) customers") {
                ForEach(shown) { row in
                    rowView(row, due: dueIDs.contains(row.id), targets: targets)
                }
            }
        }
        .navigationTitle("Price Rise")
        .alert("Set \(chosen.count) price rises?", isPresented: $isConfirming) {
            Button("Set rises") { setRises(chosen, targets: targets) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each one starts on its date. A backup is saved first. Nothing is sent to customers until you tell them.")
        }
        .alert("New price for \(editing?.customer.name ?? "")", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Price", text: $editText).keyboardType(.decimalPad)
            Button("Save") {
                if let row = editing, let value = Decimal(string: editText), value > 0 {
                    custom[row.id] = value
                    ticked[row.id] = true
                }
                editing = nil
            }
            Button("Cancel", role: .cancel) { editing = nil }
        }
        .alert("Price Rise", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
        .sheet(isPresented: $isTelling) { PriceRiseMessageView() }
    }

    private func price(for row: RoundStats.RiseRow, _ targets: [UUID: Decimal]?) -> Decimal {
        custom[row.id] ?? targets?[row.id] ?? row.newPrice
    }

    /// Ticked by hand, or by default when due a rise, it applies to them, and none is set yet.
    private func isTicked(_ row: RoundStats.RiseRow, due: Set<UUID>, _ targets: [UUID: Decimal]?) -> Bool {
        guard row.effective != nil else { return false }
        if let choice = ticked[row.id] { return choice }
        if let targets { return targets[row.id] != nil }
        return due.contains(row.id) && row.customer.pendingPrice == nil
    }

    @ViewBuilder
    private func rowView(_ row: RoundStats.RiseRow, due isDue: Bool, targets: [UUID: Decimal]?) -> some View {
        let customer = row.customer
        let on = isTicked(row, due: isDue ? [row.id] : [], targets)
        HStack(alignment: .top, spacing: 12) {
            Button {
                ticked[row.id] = !on
            } label: {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(row.effective == nil ? Color.secondary.opacity(0.4) : (on ? Color.accentColor : Color.secondary))
            }
            .buttonStyle(.borderless)
            .disabled(row.effective == nil)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(customer.name).font(.headline)
                    if customer.everyOther { Text("EO").font(.caption2.bold()).foregroundStyle(.blue) }
                    Spacer()
                    Button {
                        editText = NSDecimalNumber(decimal: price(for: row, targets)).stringValue
                        editing = row
                    } label: {
                        Text("\(customer.price.pounds) → \(price(for: row, targets).pounds)")
                            .font(.headline)
                            .foregroundStyle(custom[row.id] != nil ? Color.orange : Color.primary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(row.effective == nil)
                }
                Text(detail(row)).font(.caption).foregroundStyle(.secondary)
                if let pending = customer.pendingPrice, let from = customer.pendingPriceFrom {
                    Text("Set: \(pending.pounds) from \(RoundCalendar.shortWithYear(from))" + (customer.pendingPriceToldAt == nil ? " · not told yet" : " · told"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                }
            }
        }
    }

    private func detail(_ row: RoundStats.RiseRow) -> String {
        var parts = [row.customer.area].filter { !$0.isEmpty }
        if let since = row.customer.priceSince { parts.append("price since \(RoundCalendar.shortWithYear(since))") } else { parts.append("no price date") }
        if let effective = row.effective { parts.append("from \(RoundCalendar.shortWithYear(effective))") } else { parts.append("no rise: price is newer") }
        return parts.joined(separator: " · ")
    }

    private func setRises(_ rows: [RoundStats.RiseRow], targets setTargets: [UUID: Decimal]?) {
        _ = try? ExportService.writeBackup(from: modelContext, to: ExportService.backupDirectory)
        var count = 0
        for row in rows {
            guard let effective = row.effective else { continue }
            PriceRise.set(row.customer, to: price(for: row, setTargets), from: effective)
            count += 1
        }
        try? modelContext.save()
        ticked = [:]
        custom = [:]
        message = "\(count) rises set. Tap \"Tell customers\" to message them."
    }
}

/// Tells each customer with a rise set about their new price: one WhatsApp at a time, ticking off who's been told.
struct PriceRiseMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Customer.sequence) private var customers: [Customer]
    @AppStorage(PriceRise.messageKey) private var template = PriceRise.defaultMessage
    @State private var failure: String?

    private var pending: [Customer] { customers.filter { $0.pendingPrice != nil } }
    private func canMessage(_ c: Customer) -> Bool { c.contact == .whatsapp && !c.whatsAppDigits.isEmpty }
    private var nextToSend: Customer? { pending.first { canMessage($0) && $0.pendingPriceToldAt == nil } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Message", text: $template, axis: .vertical).lineLimit(3...6)
                } header: {
                    Text("Message")
                } footer: {
                    Text("{name}, {old}, {new} and {date} are filled in for each customer. Also in Settings.")
                }
                Section {
                    if let next = nextToSend {
                        Button { send(next) } label: {
                            Label("Message next: \(next.name)", systemImage: "paperplane.fill")
                                .font(.title3)
                                .padding(.vertical, 6)
                        }
                    } else if pending.contains(where: canMessage) {
                        Label("Everyone on WhatsApp has been told", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Text("Nobody here has a WhatsApp number. Tell them another way and tap Mark told.")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Opens WhatsApp with their message ready. Press Send, come back and tap again.")
                }
                Section("Customers (\(pending.count))") {
                    ForEach(pending) { customer in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(customer.name).font(.headline)
                                Text("\(customer.price.pounds) → \((customer.pendingPrice ?? 0).pounds)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if customer.pendingPriceToldAt != nil {
                                Label("Told", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            } else if canMessage(customer) {
                                Button { send(customer) } label: { Label("Send", systemImage: "paperplane") }.buttonStyle(.borderless)
                            } else {
                                Button("Mark told") { customer.pendingPriceToldAt = Date() }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tell customers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Can't open WhatsApp", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(failure ?? "") }
        }
    }

    private func send(_ customer: Customer) {
        guard let price = customer.pendingPrice, let from = customer.pendingPriceFrom else { return }
        let text = PriceRise.message(template: template, name: customer.name, old: customer.price, new: price, from: from)
        guard let url = DayMessage.whatsAppURL(digits: customer.whatsAppDigits, text: text) else { return }
        customer.pendingPriceToldAt = Date()
        UIApplication.shared.open(url) { success in
            if !success { failure = "WhatsApp couldn't be opened for \(customer.name). Check the number \(customer.phone)." }
        }
    }
}
