import Foundation
import SwiftData

#if targetEnvironment(simulator)
/// Development aid: `-SelfTest` (with `-ImportFile`) exercises the logging, undo, payment, credit and
/// round-placement logic against the imported round and prints PASS/FAIL lines. Aggregates only.
@MainActor
enum SimulatorSelfTest {
    private static var lines: [String] = []
    private static var failures = 0

    private static func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if !ok { failures += 1 }
        lines.append((ok ? "PASS " : "FAIL ") + name + (ok ? "" : " -> " + detail()))
    }

    private struct Snapshot: Equatable {
        var visits: Int
        var work: Decimal
        var owed: Decimal
        var owedCleans: Int
        init(_ customers: [Customer]) {
            visits = customers.reduce(0) { $0 + $1.allVisits.count }
            work = RoundMetrics.totals(for: customers, in: TaxYear.range(startYear: 2026)).work
            let owed = RoundMetrics.moneyOwed(customers)
            self.owed = owed.amount
            owedCleans = owed.cleans
        }
    }

    static func run(in context: ModelContext) throws -> String {
        lines = []
        failures = 0
        let all = try context.fetch(FetchDescriptor<Customer>(sortBy: [SortDescriptor(\.sequence)]))
        let today = RoundCalendar.startOfDay()

        guard let subject = all.first(where: { $0.status == .active && $0.price > 0 && !$0.everyOther && $0.outstandingBalance == 0 }) else {
            return "SELFTEST: no suitable customer"
        }
        let price = subject.price
        let base = Snapshot(all)

        // Cleaned & paid
        var undo = VisitLogger.perform(.cleanedPaid, for: subject, in: context)
        let latest = subject.allVisits.first { $0.date == today && $0.kind == .cleaned }
        check("cleaned&paid creates a visit today", latest != nil)
        check("cleaned&paid charged = price, paid in full", latest?.charged == price && latest?.paid == price && latest?.paidDate == today, "\(String(describing: latest?.charged)) \(String(describing: latest?.paid))")
        var snap = Snapshot(all)
        check("cleaned&paid adds work, not owed", snap.visits == base.visits + 1 && snap.work == base.work + price && snap.owed == base.owed, "\(snap)")
        undo()
        check("undo cleaned&paid restores everything", Snapshot(all) == base)

        // Cleaned, not paid
        undo = VisitLogger.perform(.cleanedNotPaid, for: subject, in: context)
        snap = Snapshot(all)
        check("cleaned-not-paid adds work and money owed", snap.work == base.work + price && snap.owed == base.owed + price && snap.owedCleans == base.owedCleans + 1, "\(snap)")
        undo()
        check("undo cleaned-not-paid restores everything", Snapshot(all) == base)

        // Cleaned + extra (and less)
        undo = VisitLogger.perform(.cleanedExtra(extra: 12, note: "Conservatory roof", paid: true), for: subject, in: context)
        let extraVisit = subject.allVisits.first { $0.date == today && $0.kind == .cleaned }
        check("extra adds to the charge and keeps the note", extraVisit?.charged == price + 12 && extraVisit?.note == "Conservatory roof" && extraVisit?.listPrice == price)
        undo()
        undo = VisitLogger.perform(.cleanedExtra(extra: -5, note: nil, paid: true), for: subject, in: context)
        check("negative extra (front only) lowers the charge", subject.allVisits.first { $0.date == today }?.charged == price - 5)
        undo()

        // Skipped
        undo = VisitLogger.perform(.skipped, for: subject, in: context)
        snap = Snapshot(all)
        check("skipped records a visit worth nothing", snap.visits == base.visits + 1 && snap.work == base.work && snap.owed == base.owed)
        check("skipped has kind skipped", subject.allVisits.contains { $0.date == today && $0.kind == .skipped })
        undo()
        check("undo skipped restores everything", Snapshot(all) == base)

        // Not started -> active on first clean, and back on undo
        if let fresh = all.first(where: { $0.status == .notStarted }) {
            undo = VisitLogger.perform(.cleanedPaid, for: fresh, in: context)
            check("first clean makes a not-started customer active", fresh.status == .active)
            undo()
            check("undo puts a customer back to not started", fresh.status == .notStarted)
        }

        // Payments
        if let debtor = all.first(where: { VisitLogger.unpaidVisits(for: $0).filter { $0.charged > 0 }.count >= 2 }) {
            let unpaid = VisitLogger.unpaidVisits(for: debtor)
            let oldest = unpaid[0]
            let owedBefore = Snapshot(all)
            let part = oldest.charged / 2
            var payment = VisitLogger.recordPayment(part, across: unpaid, on: today)
            check("part payment lands on the oldest clean only", oldest.paid == part && unpaid.dropFirst().allSatisfy { $0.paid == 0 } && oldest.paidDate == nil)
            check("part payment reduces owed by exactly that", Snapshot(all).owed == owedBefore.owed - part)
            payment.undo()
            check("undo part payment restores owed", Snapshot(all) == owedBefore)

            let total = unpaid.reduce(Decimal(0)) { $0 + $1.charged - $1.paid }
            payment = VisitLogger.recordPayment(total + 10, across: unpaid, on: today)
            check("paying more than owed reports the leftover", payment.leftover == 10, "\(payment.leftover)")
            check("paying everything clears the customer and dates it", VisitLogger.unpaidVisits(for: debtor).isEmpty && unpaid.allSatisfy { $0.paidDate == today })
            payment.undo()
            check("undo full payment restores owed and dates", Snapshot(all) == owedBefore && unpaid.allSatisfy { $0.paidDate == nil })
        } else {
            check("found a customer with 2+ unpaid cleans", false)
        }

        // Credit gets used up (the bug fixed this stage)
        let beforeCredit = subject.allVisits.count
        _ = VisitLogger.logCustomClean(for: subject, date: today, charged: price, paid: price + 5, note: nil, in: context)
        check("overpaying £5 gives £5 credit", subject.outstandingBalance == 5 && subject.suggestedNextPrice == price - 5, "\(subject.outstandingBalance)")
        _ = VisitLogger.perform(.cleanedPaid, for: subject, in: context)
        let next = subject.allVisits.filter { $0.creditApplied != 0 }
        check("next clean takes the credit off", next.count == 1 && next[0].charged == price - 5 && next[0].creditApplied == 5, "\(next.map(\.charged))")
        check("credit is used up afterwards", subject.outstandingBalance == 0 && subject.suggestedNextPrice == price, "\(subject.outstandingBalance)")
        _ = VisitLogger.logCustomClean(for: subject, date: today, charged: price, paid: price - 5, note: nil, in: context)
        check("underpaying £5 leaves a £5 shortfall", subject.outstandingBalance == -5 && subject.suggestedNextPrice == price + 5)
        _ = VisitLogger.perform(.cleanedPaid, for: subject, in: context)
        check("shortfall is recovered then cleared", subject.outstandingBalance == 0 && subject.suggestedNextPrice == price)
        check("self-test added the expected visits", subject.allVisits.count == beforeCredit + 4)

        // Round placement
        let anchor = all[5]
        let others = all.filter { $0 !== anchor }
        let newcomer = Customer(name: "Self Test", status: .notStarted)
        context.insert(newcomer)
        let seqBefore = Dictionary(uniqueKeysWithValues: all.map { (ObjectIdentifier($0), $0.sequence) })
        RoundOrder.place(newcomer, after: anchor, among: all + [newcomer])
        check("new customer goes straight after the chosen one", newcomer.sequence == anchor.sequence + 1)
        check("later customers shift down by one, earlier ones don't",
              others.allSatisfy { other in
                  let was = seqBefore[ObjectIdentifier(other)]!
                  return other.sequence == (was > seqBefore[ObjectIdentifier(anchor)]! ? was + 1 : was)
              })
        let sequences = (all + [newcomer]).map(\.sequence).sorted()
        check("sequence numbers stay unique", Set(sequences).count == sequences.count)
        let atEnd = Customer(name: "Self Test End", status: .notStarted)
        context.insert(atEnd)
        RoundOrder.place(atEnd, after: nil, among: all + [newcomer, atEnd])
        check("placing at the end uses the next number", atEnd.sequence == (all + [newcomer]).map(\.sequence).max()! + 1)

        // Next Up reacts to logging
        let crews = try context.fetch(FetchDescriptor<Crew>())
        let workDays = try context.fetch(FetchDescriptor<WorkDay>())
        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first
        func plan() -> RoundPlanner.Plan {
            RoundPlanner.plan(customers: all, settings: settings, crews: crews, workDays: workDays, today: today)
        }
        func listed(_ customer: Customer) -> Bool {
            let p = plan()
            return p.days.contains { $0.customers.contains { $0 === customer } } || p.later.contains { $0 === customer }
        }
        if let dueNow = plan().days.first?.customers.first(where: { !$0.everyOther }) {
            check("a customer on the round is listed", listed(dueNow))
            let skip = VisitLogger.perform(.skipped, for: dueNow, in: context)
            check("skipping keeps them on the round", listed(dueNow))
            skip()
            let done = VisitLogger.perform(.cleanedPaid, for: dueNow, in: context)
            check("cleaning them takes them off the round", !listed(dueNow))
            check("the round now carries on from them", plan().pointer === dueNow)
            done()
            check("undo puts them back on the round", listed(dueNow))
        } else {
            check("found a customer on today's round", false)
        }
        if let eo = all.first(where: { $0.everyOther && $0.status == .active && listed($0) }) {
            let off = VisitLogger.perform(.notDue, for: eo, in: context)
            check("'not due' takes an every-other customer off the round", !listed(eo))
            off()
        }

        // ---- Stage 6: price rise, frequent skips, checks (synthetic customers, removed afterwards)
        func stats() -> RoundStats { RoundStats(customers: (try? context.fetch(FetchDescriptor<Customer>())) ?? [], settings: settings, crews: crews, workDays: workDays, today: today) }
        func synthetic(_ name: String, price: Decimal = 20, status: CustomerStatus = .active, eo: Bool = false, frontOnly: Bool = false) -> Customer {
            let c = Customer(name: name, price: price, status: status)
            c.everyOther = eo; c.frontOnly = frontOnly
            context.insert(c); return c
        }
        func add(_ c: Customer, _ kind: VisitKind, daysAgo: Int, charged: Decimal = 20, paid: Decimal = 20, listPrice: Decimal = 20) {
            let v = Visit(date: RoundCalendar.london.date(byAdding: .day, value: -daysAgo, to: today)!, kind: kind, listPrice: listPrice, charged: kind == .cleaned ? charged : 0, paid: kind == .cleaned ? paid : 0)
            context.insert(v); v.customer = c
        }
        func listed(_ rows: [RoundStats.SkipRow], _ c: Customer) -> Bool { rows.contains { $0.customer === c } }

        let skipper = synthetic("ST skipper"); add(skipper, .cleaned, daysAgo: 100); add(skipper, .skipped, daysAgo: 70); add(skipper, .skipped, daysAgo: 40)
        let oneSkip = synthetic("ST one skip"); add(oneSkip, .cleaned, daysAgo: 100); add(oneSkip, .skipped, daysAgo: 70); add(oneSkip, .cleaned, daysAgo: 40)
        let eoCust = synthetic("ST eo", eo: true); add(eoCust, .cleaned, daysAgo: 150); add(eoCust, .notDue, daysAgo: 120); add(eoCust, .cleaned, daysAgo: 90); add(eoCust, .notDue, daysAgo: 60); add(eoCust, .skipped, daysAgo: 30)
        let cancelled = synthetic("ST cancelled", status: .cancelled); add(cancelled, .cleaned, daysAgo: 100); add(cancelled, .skipped, daysAgo: 70); add(cancelled, .skipped, daysAgo: 40)
        let beforeFirst = synthetic("ST early skips"); add(beforeFirst, .skipped, daysAgo: 200); add(beforeFirst, .skipped, daysAgo: 170); add(beforeFirst, .cleaned, daysAgo: 100)
        var skippers = stats().frequentSkippers()
        check("two skips in the last visits is flagged", listed(skippers, skipper) && skippers.first { $0.customer === skipper }?.skips == 2)
        check("one skip is not flagged", !listed(skippers, oneSkip))
        check("every-other off-cycle visits don't count (1 real skip)", !listed(skippers, eoCust))
        check("cancelled customers are left out", !listed(skippers, cancelled))
        check("skips before the first clean don't count", !listed(skippers, beforeFirst))
        let window = synthetic("ST window"); add(window, .cleaned, daysAgo: 400); add(window, .skipped, daysAgo: 380); add(window, .skipped, daysAgo: 360)
        for n in 0..<6 { add(window, .cleaned, daysAgo: 300 - n * 40) }
        skippers = stats().frequentSkippers()
        check("old skips outside the last 6 visits are forgotten", !listed(skippers, window))

        // under price
        let under = synthetic("ST under", price: 20); add(under, .cleaned, daysAgo: 10, paid: 15, listPrice: 20)
        let front = synthetic("ST front", price: 20, frontOnly: true); add(front, .cleaned, daysAgo: 10, paid: 15, listPrice: 20)
        let unpaid = synthetic("ST unpaid", price: 20); add(unpaid, .cleaned, daysAgo: 10, paid: 0, listPrice: 20)
        let recovered = synthetic("ST recovered", price: 20); add(recovered, .cleaned, daysAgo: 40, paid: 15, listPrice: 20); add(recovered, .cleaned, daysAgo: 10, paid: 20, listPrice: 20)
        let underRows = stats().payingUnderPrice()
        check("last clean paid below price is flagged", underRows.contains { $0.customer === under && $0.lastPaid == 15 })
        check("front-only customers are left out", !underRows.contains { $0.customer === front })
        check("an unpaid clean isn't 'paying under'", !underRows.contains { $0.customer === unpaid })
        check("only the latest payment counts", !underRows.contains { $0.customer === recovered })

        // data issues
        let dup = synthetic("ST dup"); add(dup, .cleaned, daysAgo: 5); add(dup, .cleaned, daysAgo: 5)
        let future = synthetic("ST future"); add(future, .cleaned, daysAgo: -3)
        let issues = stats().dataIssues()
        check("two visits on one day is flagged", issues.contains { $0.customer === dup })
        check("a visit dated in the future is flagged", issues.contains { $0.customer === future })
        check("normal customers aren't flagged", !issues.contains { $0.customer === skipper })

        // price rise end to end
        let riser = synthetic("ST riser", price: 15)
        let recent = synthetic("ST recent", price: 20); recent.priceSince = RoundCalendar.london.date(byAdding: .month, value: -6, to: today)
        let brandNew = synthetic("ST brand new", price: 20); brandNew.priceSince = today
        let savedRiseDate = settings?.priceRiseDate
        settings?.priceRiseDate = today
        let rows = stats().risePreview()
        func row(_ c: Customer) -> RoundStats.RiseRow? { rows.first { $0.customer === c } }
        check("15 rises to 16", row(riser)?.newPrice == 16 && row(riser)?.effective == today)
        check("a price changed 6 months ago waits", row(recent)?.effective == RoundCalendar.london.date(byAdding: .month, value: 6, to: today))
        check("a price that starts today gets no rise", row(brandNew)?.effective == nil && row(brandNew)?.extraPerCycle == 0)
        let applied = RoundStats.applyRises(rows.filter { ($0.effective.map { $0 <= today } ?? false) && ($0.customer === riser || $0.customer === recent || $0.customer === brandNew) }, in: context)
        check("apply changes only those whose rise has taken effect", applied == 1 && riser.price == 16 && recent.price == 20 && brandNew.price == 20, "\(applied) \(riser.price)")
        check("apply records the price history and price since", riser.priceSince == today && (riser.priceChanges ?? []).contains { $0.oldPrice == 15 && $0.newPrice == 16 && $0.reason == .rise })
        check("applying twice does nothing more", RoundStats.applyRises(stats().risePreview().filter { $0.customer === riser }, in: context) == 0 && riser.price == 16)
        settings?.priceRiseDate = savedRiseDate

        // ---- Customers screen: filters and reordering
        let everyone = try context.fetch(FetchDescriptor<Customer>(sortBy: [SortDescriptor(\.sequence)]))
        if let sample = everyone.first(where: { !$0.round.isEmpty && !$0.area.isEmpty && !$0.address.isEmpty }) {
            var c = CustomerFilter.Criteria()
            check("no filter shows everyone", CustomerFilter.apply(c, to: everyone).count == everyone.count && !c.isActive)
            c.round = sample.round
            let byRound = CustomerFilter.apply(c, to: everyone)
            check("round filter keeps only that round", !byRound.isEmpty && byRound.allSatisfy { $0.round == sample.round } && byRound.count == everyone.filter { $0.round == sample.round }.count)
            c.area = sample.area
            check("round and area together narrow further", CustomerFilter.apply(c, to: everyone).allSatisfy { $0.round == sample.round && $0.area == sample.area })
            c = .init(); c.status = .cancelled
            check("status filter", CustomerFilter.apply(c, to: everyone).count == everyone.filter { $0.status == .cancelled }.count)
            c = .init(); c.search = String(sample.address.prefix(6)).uppercased()
            check("search ignores case and matches the address", CustomerFilter.apply(c, to: everyone).contains { $0 === sample })
            c = .init(); c.search = "   "
            check("a blank search is not a filter", !c.isActive && CustomerFilter.apply(c, to: everyone).count == everyone.count)
            c = .init(); c.search = "zzzz-no-such-customer-zzzz"
            check("no match shows nothing", CustomerFilter.apply(c, to: everyone).isEmpty)
        }
        let originalOrder = everyone.map(\.id)
        RoundOrder.move(everyone, from: IndexSet(integer: 0), to: 6)   // first customer to position 6
        let afterMove = try context.fetch(FetchDescriptor<Customer>(sortBy: [SortDescriptor(\.sequence)]))
        check("dragging the first customer to position 6 puts them there", afterMove[5].id == originalOrder[0])
        check("the others slide up one place and keep their order", Array(afterMove.prefix(5)).map(\.id) == Array(originalOrder[1...5]) && afterMove.dropFirst(6).map(\.id) == Array(originalOrder.dropFirst(6)))
        check("round numbers stay 1...n with no gaps", afterMove.map(\.sequence) == Array(1...afterMove.count))
        RoundOrder.move(afterMove, from: IndexSet(integer: 5), to: 0)  // and back to the front
        let restored = try context.fetch(FetchDescriptor<Customer>(sortBy: [SortDescriptor(\.sequence)]))
        check("moving back to the front restores the original order", restored.map(\.id) == originalOrder)

        // team and crews
        let appSettings = try context.fetch(FetchDescriptor<AppSettings>()).first!
        let crewList = try context.fetch(FetchDescriptor<Crew>())
        let workDayList = try context.fetch(FetchDescriptor<WorkDay>())
        check("team list is worked out from the crews", Set(appSettings.teamMembers) == Set(crewList.flatMap(\.members)) && !appSettings.teamMembers.isEmpty)
        let member = appSettings.teamMembers[0]
        let namesBefore = crewList.map(\.name).sorted()
        let weekBefore = appSettings.usualWeek, extraBefore = appSettings.extraDayCrew
        let diaryBefore = workDayList.map(\.crewMembers)
        try TeamEditor.renameMember(from: member, to: "Zed Test", settings: appSettings, crews: crewList, workDays: workDayList)
        check("renaming a person updates the team and crews", !appSettings.teamMembers.contains(member) && appSettings.teamMembers.contains("Zed Test")
              && !crewList.contains { $0.members.contains(member) })
        check("renamed crews keep working in the usual week", appSettings.usualWeek.allSatisfy { week in week.isEmpty || crewList.contains { $0.name == week } }
              && (appSettings.extraDayCrew.isEmpty || crewList.contains { $0.name == appSettings.extraDayCrew }))
        check("renaming a person updates the diary", !workDayList.contains { $0.crewMembers.contains(member) })
        try TeamEditor.renameMember(from: "Zed Test", to: member, settings: appSettings, crews: crewList, workDays: workDayList)
        check("renaming back restores everything", crewList.map(\.name).sorted() == namesBefore && appSettings.usualWeek == weekBefore
              && appSettings.extraDayCrew == extraBefore && workDayList.map(\.crewMembers) == diaryBefore)
        check("can't remove someone who is in a crew", (try? TeamEditor.removeMember(member, settings: appSettings, crews: crewList)) == nil)
        check("can't add a duplicate name, any capitalisation", (try? TeamEditor.addMember(member.uppercased(), settings: appSettings)) == nil)
        try TeamEditor.addMember("  Newcomer ", settings: appSettings)
        check("adding a person trims the name", appSettings.teamMembers.last == "Newcomer")
        check("can't make a crew with the same people as another", (try? TeamEditor.addCrew(members: Set(crewList[0].members), dayTarget: 100, settings: appSettings, crews: crewList, context: context)) == nil)
        let solo = try TeamEditor.addCrew(members: ["Newcomer"], dayTarget: 150, settings: appSettings, crews: crewList, context: context)
        check("a new crew is named after its people", solo.name == "Newcomer alone" && solo.dayTarget == 150)
        appSettings.usualWeek[3] = solo.name
        appSettings.extraDayCrew = solo.name
        TeamEditor.deleteCrew(solo, settings: appSettings, context: context)
        check("deleting a crew clears it from the usual week", appSettings.usualWeek[3].isEmpty && appSettings.extraDayCrew.isEmpty)
        try TeamEditor.removeMember("Newcomer", settings: appSettings, crews: crewList)
        appSettings.usualWeek = weekBefore
        appSettings.extraDayCrew = extraBefore
        try context.save()
        check("team tidy-up leaves the original crews", try context.fetchCount(FetchDescriptor<Crew>()) == crewList.count && !appSettings.teamMembers.contains("Newcomer"))

        // exports
        let exportable = try context.fetch(FetchDescriptor<Customer>(sortBy: [SortDescriptor(\.sequence)]))
        let csvText = try String(contentsOf: DataExports.customersCSV(context: context), encoding: .utf8)
        let csvRows = CSVParser.parse(csvText).filter { !$0.allSatisfy(\.isEmpty) }
        check("customer CSV has a header and a row per customer", csvRows.count == exportable.count + 1 && csvRows[0].first == "Name")
        let sample = exportable.first { $0.notes.count > 0 } ?? exportable[0]
        let sampleRow = csvRows.first { $0.first == sample.name }
        check("customer CSV keeps address, price and notes", sampleRow?[1] == sample.address && sampleRow.flatMap { CSVParser.parsePrice($0[3]) } == sample.price
              && sampleRow?.last == sample.notes.joined(separator: " | "))
        let ledgerText = try String(contentsOf: DataExports.incomeListCSV(taxYear: 2026, includeNames: false, context: context), encoding: .utf8)
        let ledgerRows = CSVParser.parse(ledgerText)
        let yearTotals = RoundMetrics.totals(for: exportable, in: TaxYear.range(startYear: 2026))
        check("income list has a line per clean", ledgerRows.filter { $0.first.map { $0.hasPrefix("20") } ?? false }.count == yearTotals.cleans)
        check("income list total matches the tax year work", ledgerRows.first { $0.first == "Total charged" }?[1] == NSDecimalNumber(decimal: yearTotals.work).stringValue)
        let anonymous = try String(contentsOf: DataExports.analysisReport(includeNames: false, context: context), encoding: .utf8)
        var identifying = 0
        for person in exportable.prefix(80) where person.name.count > 5 {
            if anonymous.contains(person.name) { identifying += 1 }
            else if person.address.count > 8, anonymous.contains(person.address) { identifying += 1 }
        }
        check("anonymous analysis report has no names or addresses", identifying == 0, "\(identifying) found")
        let reportCleans = anonymous.components(separatedBy: "\n").filter { $0.hasPrefix("| C") && $0.contains("| cleaned |") }.count
        var storedCleans = 0
        for person in exportable { storedCleans += person.allVisits.filter { $0.kind == .cleaned }.count }
        check("analysis report has every visit", reportCleans == storedCleans, "\(reportCleans) vs \(storedCleans)")
        let named = try String(contentsOf: DataExports.analysisReport(includeNames: true, context: context), encoding: .utf8)
        check("named analysis report includes names", named.contains(exportable[0].name))
        var longNote: String?
        for person in exportable { if let note = person.notes.first(where: { $0.count > 12 }) { longNote = note; break } }
        check("analysis report never includes notes", longNote.map { !named.contains($0) && !anonymous.contains($0) } ?? true)

        // customer CSV round trip: export, delete two, import the file back
        let roundTrip = CSVParser.parse(csvText).filter { !$0.allSatisfy(\.isEmpty) }
        let detected = CustomerCSVImport.autoDetectedMapping(for: roundTrip[0])
        check("CSV columns are recognised from the export headings", Set(detected.values) == Set([.name, .address, .phone, .price, .round, .area, .status, .everyOther, .frontOnly, .contact, .payMethod, .accessNotes]))
        let again = CustomerCSVImport.run(mapping: detected, rows: Array(roundTrip.dropFirst()), context: context)
        check("importing the same customers again adds nobody", again.imported == 0 && again.duplicates == exportable.count - 0, "\(again.imported) added, \(again.duplicates) dupes")
        let gone = exportable.filter { !$0.notes.isEmpty && $0.status == .active }.prefix(2).map { $0 }
        let goneFacts = gone.map { ($0.name, $0.address, $0.price, $0.round, $0.area, $0.status, $0.everyOther, $0.frontOnly, $0.notes) }
        for person in gone { context.delete(person) }
        try context.save()
        let back = CustomerCSVImport.run(mapping: detected, rows: Array(roundTrip.dropFirst()), context: context)
        check("only the two deleted customers come back", back.imported == gone.count && back.duplicates == exportable.count - gone.count, "\(back.imported) added")
        let restoredAll = try context.fetch(FetchDescriptor<Customer>())
        var allMatch = !goneFacts.isEmpty
        for fact in goneFacts {
            let match = restoredAll.first { $0.name == fact.0 && $0.address == fact.1 }
            if match?.price != fact.2 || match?.round != fact.3 || match?.area != fact.4 || match?.status != fact.5
                || match?.everyOther != fact.6 || match?.frontOnly != fact.7 || match?.notes != fact.8 { allMatch = false }
        }
        check("their price, round, area, status, flags and notes survive", allMatch)
        let nameOnly = CustomerCSVImport.run(mapping: [0: .firstName, 1: .lastName, 2: .price], rows: [["Zed", "Testington", "12"], ["Zed", "Testington", "12"]], context: context)
        check("first and last name columns make one name, and a repeat is skipped", nameOnly.imported == 1 && nameOnly.duplicates == 1)
        if let zed = try context.fetch(FetchDescriptor<Customer>()).first(where: { $0.name == "Zed Testington" }) { context.delete(zed) }
        try context.save()

        // clear cleaning history (destructive, so last)
        for c in [skipper, oneSkip, eoCust, cancelled, beforeFirst, window, under, front, unpaid, recovered, dup, future, riser, recent, brandNew] { context.delete(c) }
        try context.save()
        let before = try context.fetch(FetchDescriptor<Customer>())
        let prices = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0.price) })
        let notes = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0.notes) })
        let cleared = try ImportService.clearCleaningHistory(context: context, backupDirectory: nil)
        let after = try context.fetch(FetchDescriptor<Customer>())
        let visitsLeft = try context.fetchCount(FetchDescriptor<Visit>())
        let diaryLeft = try context.fetchCount(FetchDescriptor<WorkDay>())
        let tipsLeft = try context.fetchCount(FetchDescriptor<Tip>())
        let settingsLeft = try context.fetchCount(FetchDescriptor<AppSettings>())
        let crewsLeft = try context.fetchCount(FetchDescriptor<Crew>())
        check("clear history removes the visits", cleared.visits > 0 && visitsLeft == 0)
        check("clear history removes diary and tips", diaryLeft == 0 && tipsLeft == 0)
        check("clear history keeps every customer, price and note", after.count == before.count && after.allSatisfy { prices[$0.id] == $0.price && notes[$0.id] == $0.notes })
        check("no money owed or work left", RoundMetrics.moneyOwed(after).cleans == 0 && RoundMetrics.totals(for: after, in: TaxYear.range(startYear: 2026)).work == 0)
        check("settings and crews are kept", settingsLeft == 1 && crewsLeft > 0)

        lines.append(failures == 0 ? "SELFTEST: ALL \(lines.count) CHECKS PASSED" : "SELFTEST: \(failures) FAILED")
        return lines.joined(separator: "\n")
    }
}
#endif
