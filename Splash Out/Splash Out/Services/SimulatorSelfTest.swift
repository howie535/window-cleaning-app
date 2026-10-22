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
            let balanceBefore = debtor.outstandingBalance
            payment = VisitLogger.recordPayment(total + 10, across: unpaid, on: today)
            check("paying more than owed keeps the extra as credit", payment.leftover == 0 && debtor.outstandingBalance == balanceBefore + 10, "\(payment.leftover) \(debtor.outstandingBalance)")
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
        func dayIndex(of customer: Customer, in p: RoundPlanner.Plan) -> Int? { p.days.firstIndex { $0.rows.contains { $0.customer === customer } } }
        func stateOf(_ customer: Customer, in p: RoundPlanner.Plan) -> NextUp.State? {
            for day in p.days { if let row = day.rows.first(where: { $0.customer === customer }) { return row.state } }
            return nil
        }
        func listed(_ customer: Customer) -> Bool {
            let p = plan()
            return p.days.contains { $0.customers.contains { $0 === customer } } || p.later.contains { $0 === customer }
        }
        let planBefore = plan()
        if let first = planBefore.days.first, first.date == today, let dueNow = first.customers.first(where: { !$0.everyOther }) {
            check("a customer on today's round is listed", listed(dueNow))
            let todaysPlanned = Set(first.customers.map(\.id))
            let skip = VisitLogger.perform(.skipped, for: dueNow, in: context)
            var after = plan()
            check("a skip stays on today, shown as skipped and not counted", stateOf(dueNow, in: after) == .skippedToday && dayIndex(of: dueNow, in: after) == 0 && !after.days[0].customers.contains { $0 === dueNow })
            skip()
            let todayBefore = Set(first.rows.filter { $0.state.counts || $0.isDone }.map(\.customer.id))
            let doneBefore = first.doneTotal
            let done = VisitLogger.perform(.cleanedPaid, for: dueNow, in: context)
            after = plan()
            check("a clean stays on today, ticked, and counts towards today", stateOf(dueNow, in: after) == .cleanedToday && dayIndex(of: dueNow, in: after) == 0 && after.days[0].doneTotal - doneBefore == dueNow.price)
            let stillToday = Set(after.days[0].rows.filter { $0.state.counts || $0.isDone }.map(\.customer.id))
            check("marking a clean doesn't pull new customers onto today", stillToday.isSubset(of: todayBefore) && stillToday.contains(dueNow.id), "\(stillToday.subtracting(todayBefore).count) new")
            done()
            check("undo puts them back on the plan", listed(dueNow) && stateOf(dueNow, in: plan()) == .planned)

            // Cleaning someone further down first doesn't move the customers above them.
            if planBefore.days.count > 2, let further = planBefore.days[2].customers.first(where: { !$0.everyOther }) {
                let jump = VisitLogger.perform(.cleanedNotPaid, for: further, in: context)
                after = plan()
                let firstDayNow = Set(after.days[0].customers.map(\.id))
                let secondDayBefore = Set(planBefore.days[1].customers.map(\.id))
                let stayed = todaysPlanned.subtracting([further.id]).filter { firstDayNow.contains($0) }.count
                check("cleaning out of order keeps today's customers on today", Double(stayed) >= Double(todaysPlanned.count) * 0.8, "\(stayed) of \(todaysPlanned.count)")
                check("cleaning out of order doesn't send anyone to the end of the round", secondDayBefore.allSatisfy { id in after.days.prefix(4).contains { $0.rows.contains { $0.customer.id == id } } })
                check("the customer cleaned out of order shows on today, done", stateOf(further, in: after) == .cleanedToday && dayIndex(of: further, in: after) == 0)
                let again = plan()
                check("a customer cleaned today never shows again as still to do", !again.days.contains { $0.customers.contains { $0 === further } } && !again.later.contains { $0 === further })
                jump()
            }

            // Booking keeps a customer on their day.
            if planBefore.days.count > 3 {
                let target = planBefore.days[3].date
                dueNow.bookedFor = target
                after = plan()
                check("a booked customer goes on their booked day", stateOf(dueNow, in: after) == .booked && after.days.firstIndex { $0.date == target } == dayIndex(of: dueNow, in: after))
                let other = planBefore.days[0].customers.first { $0 !== dueNow && !$0.everyOther }
                let otherDone = other.map { VisitLogger.perform(.cleanedPaid, for: $0, in: context) }
                check("a booking survives other cleans", stateOf(dueNow, in: plan()) == .booked)
                otherDone?()
                let cleared = VisitLogger.perform(.skipped, for: dueNow, in: context)
                check("logging a visit clears the booking", dueNow.bookedFor == nil)
                cleared()
                check("undo puts the booking back", dueNow.bookedFor == target)
                dueNow.bookedFor = nil
            }
        } else {
            // Only possible on a working day: on a day off (e.g. a Thursday) there's no round list for today.
            if let first = planBefore.days.first, first.date == today, first.target > 0 {
                check("found a customer on today's round", false)
            } else {
                lines.append("NOTE today isn't a working day, so the today's-round checks were skipped")
            }
        }
        if let eo = all.first(where: { $0.everyOther && $0.status == .active && listed($0) }) {
            let off = VisitLogger.perform(.notDue, for: eo, in: context)
            check("'not due' keeps an every-other customer on today, not counted", stateOf(eo, in: plan()) == .notDueToday)
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

        // ---- Due when it's their turn (day two: Steve Caton and Sharon Hughes jumped ahead of their neighbours)
        do {
            let cal = RoundCalendar.london
            func ago(_ d: Int) -> Date { cal.date(byAdding: .day, value: -d, to: today)! }
            func cand(_ seq: Int, _ cleaned: Int) -> NextUp.Candidate {
                NextUp.Candidate(key: seq, sequence: seq, isListable: true, price: 20, everyOther: false,
                                 lastCleaned: ago(cleaned), lastNotDue: nil, lastVisit: ago(cleaned), lastVisitBeforeToday: ago(cleaned))
            }
            // 1-5 done yesterday (where the round got to); 6-15 due; 16-25 cleaned 32 days ago (due in a few days)
            // except 20, missed last time; 26-30 due.
            var people = (1...5).map { cand($0, 1) } + (6...15).map { cand($0, 40) } + (16...25).map { cand($0, $0 == 20 ? 60 : 32) }
            people += (26...30).map { cand($0, 40) }
            let days = [0, 2, 4, 7, 9, 11].map { NextUp.Day(date: cal.date(byAdding: .day, value: $0, to: today)!, target: 100) }
            let placed = NextUp.plan(people, days: days, today: today, overbook: 0, hideWeeks: 5, lapDays: 35, calendar: cal)
            func dayOf(_ seq: Int) -> Int? { placed.first { $0.key == seq }?.dayIndex }
            let day2 = placed.filter { $0.dayIndex == 2 }.map(\.key).sorted()
            check("missed customer waits for their neighbours, not the front of the list", day2 == [16, 17, 18, 19, 20], "\(day2)")
            check("neighbours due by the day the round reaches them are on the list", (16...25).allSatisfy { dayOf($0) != nil })
            let day0 = placed.filter { $0.dayIndex == 0 }.map(\.key).sorted()
            check("today carries on in round order from the start of the day", day0 == [6, 7, 8, 9, 10], "\(day0)")
        }

        // ---- Day five: average price, ending the day early, price rise to target, Direct Debit
        do {
            let a = Customer(name: "A", price: 10); let b = Customer(name: "B", price: 20); b.altPrice = 12
            let c = Customer(name: "C", price: 28, status: .notStarted); let d = Customer(name: "D", price: 99, status: .cancelled)
            let avg = RoundMetrics.averagePrice([a, b, c, d])
            check("average price: list prices ÷ customers, two-price as the middle, not started in, cancelled out", avg.customers == 3 && avg.average == 18, "\(avg)")
            check("customers on the round include not started", RoundMetrics.onRound([a, b, c, d]).count == 3)

            check("Direct Debit per clean = monthly × 12 ÷ (52 ÷ 5), to the penny", DirectDebit.perClean(monthly: 15) == Decimal(string: "17.31")
                  && DirectDebit.perClean(monthly: 13) == 15)


            let cal = RoundCalendar.london
            let old = cal.date(byAdding: .day, value: -40, to: today)!
            let cands = (1...5).map { NextUp.Candidate(key: $0, sequence: $0, isListable: true, price: 20, everyOther: false, lastCleaned: old, lastNotDue: nil, lastVisit: old, lastVisitBeforeToday: old) }
            let days = [NextUp.Day(date: today, target: 100), NextUp.Day(date: cal.date(byAdding: .day, value: 1, to: today)!, target: 100)]
            let ended = NextUp.plan(cands, days: days, today: today, overbook: 0, hideWeeks: 5, lapDays: 35, todayEnded: true, calendar: cal)
            check("moving the rest to the next day leaves nobody else on today", !ended.contains { $0.dayIndex == 0 } && ended.filter { $0.dayIndex == 1 }.count == 5)
        }

        // ---- Skips only top today back up to its real target (day three: Jay jumped from Monday to today)
        do {
            let cal = RoundCalendar.london
            let old = cal.date(byAdding: .day, value: -40, to: today)!
            func visited(_ seq: Int, _ kind: VisitKind, _ charged: Decimal) -> NextUp.Candidate {
                NextUp.Candidate(key: seq, sequence: seq, isListable: true, price: 20, everyOther: false, lastCleaned: kind == .cleaned ? today : old,
                                 lastNotDue: nil, lastVisit: today, lastVisitBeforeToday: old, visitedToday: kind, chargedToday: charged)
            }
            let jay = NextUp.Candidate(key: 9, sequence: 9, isListable: true, price: 20, everyOther: false, lastCleaned: old,
                                       lastNotDue: nil, lastVisit: old, lastVisitBeforeToday: old)
            let days = [NextUp.Day(date: today, target: 300), NextUp.Day(date: cal.date(byAdding: .day, value: 5, to: today)!, target: 300)]
            let pastTarget = [visited(1, .cleaned, 100), visited(2, .cleaned, 100), visited(3, .cleaned, 110), visited(4, .skipped, 0), jay]   // £310: Jay would fit in £330
            let placedPast = NextUp.plan(pastTarget, days: days, today: today, overbook: 0.1, hideWeeks: 5, lapDays: 35, calendar: cal)
            check("a skip doesn't pull tomorrow's customer in once today is past its target", placedPast.first { $0.key == 9 }?.dayIndex == 1)
            let noSkip = [visited(1, .cleaned, 100), visited(2, .cleaned, 100), visited(3, .cleaned, 110), jay]
            check("without a skip the day still fills to target + 10%", NextUp.plan(noSkip, days: days, today: today, overbook: 0.1, hideWeeks: 5, lapDays: 35, calendar: cal).first { $0.key == 9 }?.dayIndex == 0)
            let short = [visited(1, .cleaned, 100), visited(2, .cleaned, 100), visited(3, .cleaned, 80), visited(4, .skipped, 0), jay]
            let placedShort = NextUp.plan(short, days: days, today: today, overbook: 0.1, hideWeeks: 5, lapDays: 35, calendar: cal)
            check("a skip that takes today below target tops it back up", placedShort.first { $0.key == 9 }?.dayIndex == 0)
        }

        // ---- Clusters kept together (day two)
        do {
            check("street match ignores house numbers and names", RoundGrouping.sameStreet("Blue Haze Lon Pendyffryn", "34 Lon Pendyffryn")
                  && RoundGrouping.sameStreet("2 Spring Gardens", "5 spring gardens") && RoundGrouping.sameStreet("12 Broadway", "25 Broadway")
                  && RoundGrouping.sameStreet("Unit 1 Kinmel Dr, Bodelwyddan", "4 Kinmel Dr")
                  && RoundGrouping.sameStreet("122 Llysfaen Road", "120 Llysfaen Rd")
                  && RoundGrouping.sameStreet("Coddington, High St", "12 High Street"))
            check("different streets don't match", !RoundGrouping.sameStreet("12 The Dale", "9 Spring Gardens")
                  && !RoundGrouping.sameStreet("Rd to Llanddulas", "Tan yr Ogof Hall") && !RoundGrouping.sameStreet("", ""))
            let auto = RoundGrouping.groups([("1 A Street", nil), ("3 A Street", nil), ("2 B Road", nil), ("5 A Street", nil)])
            check("clusters are runs of neighbours on one street", auto == [0, 0, 1, 2], "\(auto)")
            let manual = RoundGrouping.groups([("1 A Street", nil), ("3 A Street", false), ("2 B Road", true), ("4 B Road", nil)])
            check("never / always override the street", manual == [0, 1, 1, 1], "\(manual)")

            let cal = RoundCalendar.london
            func cand(_ seq: Int, _ group: Int) -> NextUp.Candidate {
                let last = cal.date(byAdding: .day, value: -40, to: today)!
                return NextUp.Candidate(key: seq, sequence: seq, isListable: true, price: 20, everyOther: false, lastCleaned: last,
                                        lastNotDue: nil, lastVisit: last, lastVisitBeforeToday: last, group: group)
            }
            // 1-4 one street (£80), 5-7 another (£60), 8 on its own (£20), 9-12 a third street (£80). £100 a day.
            let people = (1...4).map { cand($0, 0) } + (5...7).map { cand($0, 1) } + [cand(8, 2)] + (9...12).map { cand($0, 3) }
            let days = (0..<4).map { NextUp.Day(date: cal.date(byAdding: .day, value: $0 * 2, to: today)!, target: 100) }
            let placed = NextUp.plan(people, days: days, today: today, overbook: 0, hideWeeks: 5, lapDays: 35, calendar: cal)
            func on(_ day: Int) -> [Int] { placed.filter { $0.dayIndex == day }.map(\.key).sorted() }
            check("a cluster that won't fit starts the next day; a later one that fits fills the gap", on(0) == [1, 2, 3, 4, 8] && on(1).starts(with: [5, 6, 7]),
                  "\(on(0)) / \(on(1))")
            check("everyone placed exactly once with clusters", placed.count == 12 && Set(placed.map(\.key)).count == 12)
            let big = (1...8).map { cand($0, 0) }
            let bigPlaced = NextUp.plan(big, days: days, today: today, overbook: 0, hideWeeks: 5, lapDays: 35, calendar: cal)
            check("a cluster bigger than a whole day is split", bigPlaced.filter { $0.dayIndex == 0 }.count == 5 && bigPlaced.filter { $0.dayIndex == 1 }.count == 3)
            // £90 done, next cluster £20: only a little over (£110 of £100), so it goes on whole and keeps round order.
            let small = [cand(1, 0), cand(2, 0), cand(3, 0), cand(4, 0)].map { var c = $0; c.price = 22.5; return c } + [cand(5, 1), cand(6, 1)].map { var c = $0; c.price = 10; return c } + [cand(7, 2)]
            let smallPlaced = NextUp.plan(small, days: days, today: today, overbook: 0, hideWeeks: 5, lapDays: 35, calendar: cal)
            check("a cluster that only goes a little over stays in round order", smallPlaced.filter { $0.dayIndex == 0 }.map(\.key).sorted() == [1, 2, 3, 4, 5, 6])
        }

        // ---- Day-one fixes (Phase B): payments in advance, second price, edit and delete
        let advance = synthetic("ST advance"); add(advance, .cleaned, daysAgo: 30)
        let ahead = VisitLogger.recordPayment(15, across: [], on: today, creditTo: advance.allVisits.first)
        check("payment with nothing owed becomes credit", ahead.leftover == 0 && advance.outstandingBalance == 15 && advance.suggestedNextPrice == 5, "\(advance.outstandingBalance)")
        ahead.undo()
        check("undo advance payment removes the credit", advance.outstandingBalance == 0)

        let debtor2 = synthetic("ST owes"); add(debtor2, .cleaned, daysAgo: 70, paid: 0); add(debtor2, .cleaned, daysAgo: 35, paid: 0)
        let payOff = VisitLogger.cleanAndPayOff(.cleanedPaid, for: debtor2, in: context)
        check("cleaned & paid plus what they owed clears every clean", payOff.paidOff == 40 && VisitLogger.unpaidVisits(for: debtor2).isEmpty && debtor2.allVisits.count == 3)
        payOff.undo()
        check("one undo takes back the clean and the payment", debtor2.allVisits.count == 2 && RoundMetrics.moneyOwed([debtor2]).amount == 40)
        context.delete(debtor2)


        // Day three: front only, the owed reminder and the round review.
        do {
            let front = synthetic("ST front only"); add(front, .cleaned, daysAgo: 35)
            check("no front-only price before the first one", VisitLogger.lastFrontOnlyPrice(for: front) == nil)
            let undoFront = VisitLogger.perform(.frontOnly(price: 9, paid: false), for: front, in: context)
            let frontVisit = front.allVisits.first { $0.date == today }
            check("front only charges the amount given and is marked front only", frontVisit?.charged == 9 && frontVisit?.note == "Front only"
                  && VisitLogger.lastFrontOnlyPrice(for: front) == 9 && RoundMetrics.moneyOwed([front]).amount == 9)
            let reminder = OwedReminder.text(template: OwedReminder.defaultTemplate, for: front)
            check("owed reminder fills in name, amount and cleans", reminder.contains("ST front only") && reminder.contains("£9") && reminder.contains("clean") && !reminder.contains("{"))
            undoFront()
            check("cheap points: 1 per 10% under the average, none under 10%, at most 4", RoundReview.cheapPoints(price: 20, average: 20) == 0
                  && RoundReview.cheapPoints(price: 15, average: 20) == 2 && RoundReview.cheapPoints(price: 2, average: 20) == 4)
            let lonely = synthetic("ST lonely", price: 8); lonely.address = "1 Nowhere Lane Test"; lonely.sequence = 99_999
            add(lonely, .skipped, daysAgo: 30); add(lonely, .skipped, daysAgo: 60); add(lonely, .cleaned, daysAgo: 90, paid: 0)
            let review = RoundReview.rows(customers: (try? context.fetch(FetchDescriptor<Customer>())) ?? [], today: today)
            let lonelyRow = review.rows.first { $0.customer === lonely }
            check("a cheap house on its own is flagged, but its skips don't count against it", lonelyRow != nil && (lonelyRow?.reasons.contains("On its own") ?? false)
                  && !(lonelyRow?.reasons.contains { $0.hasPrefix("Skips") } ?? true), "\(String(describing: lonelyRow?.reasons))")
            lonely.frontOnly = true
            let reviewFront = RoundReview.rows(customers: (try? context.fetch(FetchDescriptor<Customer>())) ?? [], today: today, threshold: 1)
            let frontRow = reviewFront.rows.first { $0.customer === lonely }
            check("a front-only house is never counted as cheap", frontRow?.frontOnly == true && !(frontRow?.reasons.contains { $0.hasSuffix("under average") } ?? true),
                  "\(String(describing: frontRow?.reasons))")
            for c in [front, lonely] { context.delete(c) }
        }

        // Changing groups by hand.
        do {
            let specs = [("ST g1", "1 Zzalpha Street"), ("ST g2", "3 Zzalpha Street"), ("ST g3", "2 Zzbravo Road"), ("ST g4", "4 Zzbravo Road"),
                         ("ST g5", "Lone House Zzcharlie Lane"), ("ST g6", "1 Zzdelta Avenue"), ("ST g7", "5 Zzdelta Avenue")]
            var made: [Customer] = []
            for (i, spec) in specs.enumerated() {
                let c = synthetic(spec.0); c.address = spec.1; c.sequence = 900_000 + i; made.append(c)
            }
            let (g1, g3, g4, g5, g6) = (made[0], made[2], made[3], made[4], made[5])
            func everyone() -> [Customer] { (try? context.fetch(FetchDescriptor<Customer>())) ?? [] }
            func names() -> [[String]] {
                GroupEditing.clusters(everyone()).map { $0.members.filter { made.contains($0) }.map(\.name) }.filter { !$0.isEmpty }
            }
            func cluster(of c: Customer) -> GroupEditing.Cluster { GroupEditing.clusters(everyone()).first { $0.members.contains { $0 === c } }! }
            check("groups start as the streets", names() == [["ST g1", "ST g2"], ["ST g3", "ST g4"], ["ST g5"], ["ST g6", "ST g7"]], "\(names())")
            GroupEditing.join([g5], into: cluster(of: g4), all: everyone())
            check("joining the group before needs no move", names() == [["ST g1", "ST g2"], ["ST g3", "ST g4", "ST g5"], ["ST g6", "ST g7"]] && g5.sequence == 900_004, "\(names())")
            GroupEditing.standAlone(g5, all: everyone())
            check("on its own again", names() == [["ST g1", "ST g2"], ["ST g3", "ST g4"], ["ST g5"], ["ST g6", "ST g7"]], "\(names())")
            GroupEditing.join([g5], into: cluster(of: g6), all: everyone())
            check("joining the group after makes it lead that group", names() == [["ST g1", "ST g2"], ["ST g3", "ST g4"], ["ST g5", "ST g6", "ST g7"]], "\(names())")
            GroupEditing.standAlone(g5, all: everyone())
            GroupEditing.join([g5], into: cluster(of: g1), all: everyone())
            let order = made.sorted { $0.sequence < $1.sequence }.map(\.name)
            check("joining a group further away moves the house in the round", order == ["ST g1", "ST g2", "ST g5", "ST g3", "ST g4", "ST g6", "ST g7"]
                  && names() == [["ST g1", "ST g2", "ST g5"], ["ST g3", "ST g4"], ["ST g6", "ST g7"]], "\(order) \(names())")
            GroupEditing.join(cluster(of: g3).members, into: cluster(of: g6), all: everyone())
            check("whole groups merge with the group next to them", names() == [["ST g1", "ST g2", "ST g5"], ["ST g3", "ST g4", "ST g6", "ST g7"]], "\(names())")
            GroupEditing.standAlone(g6, all: everyone())
            GroupEditing.join([g6], into: cluster(of: g1), all: everyone(), joining: false)
            check("moving next to a group further away can keep it separate", cluster(of: g6).members.first === g6 && !cluster(of: g1).members.contains { $0 === g6 }
                  && g6.sequence == cluster(of: g1).last.sequence + 1, "\(names())")
            // Customers page: drag, new group after, join the group above.
            GroupEditing.move(g6, after: g1, all: everyone())
            check("dragging onto a customer puts them after it, in its group", cluster(of: g1).members.contains { $0 === g6 }
                  && g6.sequence == g1.sequence + 1, "\(names())")
            GroupEditing.newGroup(after: g1, all: everyone())
            check("start a new group after a customer splits the group there", cluster(of: g1).last === g1 && cluster(of: g6).first === g6, "\(names())")
            GroupEditing.joinGroupAbove(g6, all: everyone())
            check("join the group above merges them back", cluster(of: g1).members.contains { $0 === g6 }, "\(names())")
            GroupEditing.move(g6, toStartOf: cluster(of: g3), all: everyone())
            check("dropping on a group's heading puts them first in it", cluster(of: g3).first === g6, "\(names())")
            check("street names read as written", RoundGrouping.streetName("27 Bron Wern") == "Bron Wern" && RoundGrouping.streetName("Coddington, High St") == "High St")
            for c in made { context.delete(c) }
            try context.save()
        }

        let twoPrice = synthetic("ST two prices"); twoPrice.altPrice = 12; twoPrice.altPriceLabel = "Front only"
        add(twoPrice, .cleaned, daysAgo: 35)
        check("two prices: the one not used last time comes next", twoPrice.nextListPrice == 12)
        let altUndo = VisitLogger.perform(.cleanedPaid, for: twoPrice, in: context)
        let altVisit = twoPrice.allVisits.first { $0.date == today }
        check("two prices: one tap charges the second price", altVisit?.charged == 12 && altVisit?.listPrice == 12, "\(String(describing: altVisit?.charged))")
        check("two prices: then back to the usual price", twoPrice.nextListPrice == 20)
        altUndo()
        let chosen = VisitLogger.perform(.cleanedAt(price: 20, paid: false), for: twoPrice, in: context)
        check("two prices: a chosen price is used", twoPrice.allVisits.first { $0.date == today }?.charged == 20 && RoundMetrics.moneyOwed([twoPrice]).amount == 20)
        chosen()
        twoPrice.altPrice = 20
        check("a second price equal to the usual one is ignored", twoPrice.secondPrice == nil && twoPrice.nextListPrice == 20)

        let editMe = synthetic("ST edit"); add(editMe, .cleaned, daysAgo: 3, charged: 45, paid: 0)
        let editVisit = editMe.allVisits[0]
        let saved = VisitSnapshot(editVisit)
        let workBefore = stats().work(from: editVisit.date, through: editVisit.date)
        editVisit.charged = 17
        check("editing a clean's charge changes the day's work", stats().work(from: editVisit.date, through: editVisit.date) == workBefore - 28)
        saved.restore(editVisit)
        check("undoing an edit puts it back", editVisit.charged == 45 && stats().work(from: editVisit.date, through: editVisit.date) == workBefore)

        let doomed = synthetic("ST delete me"); add(doomed, .cleaned, daysAgo: 2); add(doomed, .skipped, daysAgo: 40)
        try context.save()
        let visitCount = try context.fetchCount(FetchDescriptor<Visit>())
        let goneDay = RoundCalendar.london.date(byAdding: .day, value: -2, to: today)!
        let dayWork = stats().work(from: goneDay, through: goneDay)
        context.delete(doomed)
        try context.save()
        check("deleting a customer removes their visits", try context.fetchCount(FetchDescriptor<Visit>()) == visitCount - 2)
        check("deleting a customer takes their cleans out of the totals", stats().work(from: goneDay, through: goneDay) == dayWork - 20)
        for c in [advance, twoPrice, editMe] { context.delete(c) }
        try context.save()

        do {
            let everyone = try context.fetch(FetchDescriptor<Customer>())
            let clock = ContinuousClock()
            func ms(_ d: Duration) -> Int { Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000) }
            let tCold = clock.measure { _ = RoundPlanner.plan(customers: everyone, settings: settings, crews: crews, workDays: workDays, today: today) }
            let tPlan = clock.measure { _ = RoundPlanner.plan(customers: everyone, settings: settings, crews: crews, workDays: workDays, today: today) }
            let tStats = clock.measure {
                let s = RoundStats(customers: everyone, settings: settings, crews: crews, workDays: workDays, today: today)
                _ = s.thisWeek; _ = s.weeks; _ = s.skipRate; _ = s.averagePerHouseByDay()
                _ = s.workRate(); _ = s.risesDue()
            }
            let tOwed = clock.measure { _ = RoundMetrics.moneyOwed(everyone); _ = everyone.map { VisitLogger.unpaidVisits(for: $0) } }
            // What a save does to the next plan (the second wave of lag after logging).
            let tWarm = clock.measure { _ = RoundPlanner.plan(customers: everyone, settings: settings, crews: crews, workDays: workDays, today: today) }
            try context.save()
            let tAfterSave = clock.measure { _ = RoundPlanner.plan(customers: everyone, settings: settings, crews: crews, workDays: workDays, today: today) }
            let refetched = try context.fetch(FetchDescriptor<Customer>())
            let tRefetch = clock.measure { _ = RoundPlanner.plan(customers: refetched, settings: settings, crews: crews, workDays: workDays, today: today) }
            try context.save()
            var withVisits = FetchDescriptor<Customer>()
            withVisits.relationshipKeyPathsForPrefetching = [\.visits]
            let prefetched = try context.fetch(withVisits)
            let tPrefetch = clock.measure { _ = RoundPlanner.plan(customers: prefetched, settings: settings, crews: crews, workDays: workDays, today: today) }
            try context.save()
            var visitCount = 0
            let tAllVisits = try clock.measure {
                let all = try context.fetch(FetchDescriptor<Visit>())
                var byCustomer: [PersistentIdentifier: Int] = [:]
                for v in all { _ = v.date; _ = v.kindRaw; _ = v.charged; if let id = v.customer?.persistentModelID { byCustomer[id, default: 0] += 1 } }
                visitCount = all.count
            }
            lines.append("PERF after save: customers fetched with visits \(ms(tPrefetch))ms; all \(visitCount) visits in one fetch \(ms(tAllVisits))ms")
            lines.append("PERF warm \(ms(tWarm))ms, after save \(ms(tAfterSave))ms, after save and refetch \(ms(tRefetch))ms")
            let tExport = try clock.measure { _ = try ExportService.data(from: context) }
            let tClusters = clock.measure { _ = GroupEditing.clusters(everyone) }
            try context.save()
            let cold = ModelContext(context.container)
            let coldCustomers = try cold.fetch(FetchDescriptor<Customer>())
            let tColdStats = clock.measure {
                let s = RoundStats(customers: coldCustomers, settings: settings, crews: crews, workDays: workDays, today: today)
                _ = s.weeks; _ = s.workRate()
            }
            let cold2 = ModelContext(context.container)
            let coldCustomers2 = try cold2.fetch(FetchDescriptor<Customer>())
            let coldVisits2 = try cold2.fetch(FetchDescriptor<Visit>())
            let tIndexedStats = clock.measure {
                VisitLookup.begin(coldVisits2)
                let s = RoundStats(customers: coldCustomers2, settings: settings, crews: crews, workDays: workDays, today: today)
                _ = s.weeks; _ = s.workRate()
                VisitLookup.end()
            }
            lines.append("PERF export \(ms(tExport))ms, clusters \(ms(tClusters))ms (x\(everyone.count) rows = \(ms(tClusters) * everyone.count)ms), cold stats \(ms(tColdStats))ms vs indexed \(ms(tIndexedStats))ms")
            lines.append("PERF plan first \(ms(tCold))ms then \(ms(tPlan))ms, stats \(ms(tStats))ms, owed \(ms(tOwed))ms (\(everyone.count) customers)")
        }
        // Ideal figures, with inputs worked out by hand: 20 houses a workday, 3 usual days (2.5 actually worked),
        // £16 a house, 4% skips, 400 people = 390 cleans a round, £1,200 a week, 5-week round.
        let rate = RoundStats.WorkRate(housesPerDay: 20, workedDays: 50, daysPerWeek: 2.5, perHouse: 16, skipRate: 0.04, weeks: 20)
        let busy = Ideal(weeklyTarget: 1200, usualDays: 3, weeks: 5, rate: rate, people: 400, cleansPerRound: 390, periodLabel: "test", averagePrice: 16)
        func near(_ a: Decimal?, _ b: Double, _ within: Double = 0.01) -> Bool { a.map { abs(NSDecimalNumber(decimal: $0).doubleValue - b) < within } ?? false }
        check("ideal round value = £1,200 x 5 / 96%", near(busy.roundValue, 6250))
        if let p = busy.planned, let w = busy.actual {
            check("planned: 60 houses a week, £20 a house needed, £960 a week now", near(p.capacity, 60) && near(p.perHouse, 20) && near(p.incomeNow, 960) && !p.limitedByCustomers)
            check("planned: 312.5 cleans a round = 321 people with the same every-other mix", near(p.cleansNeeded, 312.5) && p.peopleNeeded == 321, "\(p.peopleNeeded)")
            check("planned: the round takes 6.24 weeks now", near(p.roundWeeksNow, 6.24))
            check("as worked: 50 houses a week, £24 a house needed, £800 a week now", near(w.capacity, 50) && near(w.perHouse, 24) && near(w.incomeNow, 800))
        } else {
            check("ideal scenarios worked out", false)
        }
        let quiet = Ideal(weeklyTarget: 1200, usualDays: 3, weeks: 5, rate: rate, people: 100, cleansPerRound: 100, periodLabel: "test", averagePrice: 16)
        check("too few customers: price uses the 19.2 houses a week the round supplies", quiet.planned.map { $0.limitedByCustomers && near($0.perHouse, 62.5) } ?? false)

        if let real = stats().workRate() {
            let s = stats()
            let yesterday = RoundCalendar.london.date(byAdding: .day, value: -1, to: today)!
            let houses = s.houses(from: s.analysisStart, through: yesterday)
            let work = s.work(from: s.analysisStart, through: yesterday)
            check("work rate £ per house = total £ / total houses", houses > 0 && near(real.perHouse, NSDecimalNumber(decimal: work / Decimal(houses)).doubleValue))
            lines.append("WORKRATE \(s.analysisLabel): \(real.housesPerDay) a day, \(real.daysPerWeek) days a week, £\(real.perHouse) a house, skips \(real.skipRate)")
        }
        if let gap = stats().roundLengthWeeks() { lines.append("ROUNDLENGTH \(gap.weeks) weeks over \(gap.gaps) gaps") }

        // Averages only count finished days: a pricey first clean this morning mustn't move them.
        do {
            let before = (stats().averagePerHouseByDay()?.average, stats().workRate())
            let early = synthetic("ST early bird", price: 95); add(early, .cleaned, daysAgo: 0, charged: 95, paid: 95, listPrice: 95)
            let after = (stats().averagePerHouseByDay()?.average, stats().workRate())
            func same(_ a: Decimal?, _ b: Decimal?) -> Bool { abs(NSDecimalNumber(decimal: (a ?? 0) - (b ?? 0)).doubleValue) < 0.000001 }
            check("today's cleans don't move the averages until the day is over",
                  same(before.0, after.0) && same(before.1?.perHouse, after.1?.perHouse) && same(before.1?.housesPerDay, after.1?.housesPerDay)
                  && before.1?.workedDays == after.1?.workedDays, "\(String(describing: before.0)) vs \(String(describing: after.0))")
            context.delete(early)
        }
        if let perHouse = stats().averagePerHouseByDay() {
            lines.append("AVGPERHOUSE £\(perHouse.average) over \(perHouse.days) days")
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
        // overall skip rate: every visit ever, cancelled customers left out
        func manualSkipRate(includingCancelled: Bool) -> Double {
            var skipped = 0, total = 0
            let everyone = (try? context.fetch(FetchDescriptor<Customer>())) ?? []
            for person in everyone where includingCancelled || person.status != .cancelled {
                for visit in person.allVisits where visit.kind != .notDue {
                    total += 1
                    if visit.kind == .skipped { skipped += 1 }
                }
            }
            return total == 0 ? 0 : Double(skipped) / Double(total)
        }
        check("skip rate counts every visit ever, without cancelled customers", abs(stats().skipRate - manualSkipRate(includingCancelled: false)) < 0.000001)
        check("a cancelled customer's skips would have changed it", abs(manualSkipRate(includingCancelled: true) - manualSkipRate(includingCancelled: false)) > 0.000001)
        // Round length: average gap over the last 12 weeks, skips and old gaps left out. The test's "today" is
        // 400 days ahead so real customers' gaps can't fall in its window; before(n) is n days before that.
        do {
            let lengthToday = RoundCalendar.london.date(byAdding: .day, value: 400, to: today)!
            func before(_ n: Int) -> Int { n - 400 }
            var testers: [Customer] = []
            for n in 0..<10 {
                let c = synthetic("ST length \(n)"); add(c, .cleaned, daysAgo: before(80)); add(c, .cleaned, daysAgo: before(38)); testers.append(c)   // 42 days
            }
            let skipper2 = synthetic("ST length skip"); add(skipper2, .cleaned, daysAgo: before(90)); add(skipper2, .skipped, daysAgo: before(50)); add(skipper2, .cleaned, daysAgo: before(10))
            let old = synthetic("ST length old"); add(old, .cleaned, daysAgo: before(200)); add(old, .cleaned, daysAgo: before(100))
            let group = testers + [skipper2, old]
            let length = RoundStats(customers: group, settings: settings, crews: crews, workDays: workDays, today: lengthToday).roundLengthWeeks()
            check("round length: average gap over 12 weeks, skips and older gaps left out", length?.gaps == 10 && length?.weeks == 6, "\(String(describing: length))")
            let newer = synthetic("ST length new"); add(newer, .cleaned, daysAgo: before(28)); add(newer, .cleaned, daysAgo: before(0))   // 28 days, ending "today"
            let withToday = RoundStats(customers: group + [newer], settings: settings, crews: crews, workDays: workDays, today: lengthToday).roundLengthWeeks()
            check("a clean logged today moves the round length straight away", withToday?.gaps == 11 && (withToday?.weeks ?? 0) < 6, "\(String(describing: withToday))")
            for c in group + [newer] { context.delete(c) }
        }

        let longAgo = synthetic("ST year window"); add(longAgo, .cleaned, daysAgo: 500); add(longAgo, .skipped, daysAgo: 450); add(longAgo, .skipped, daysAgo: 400)
        for n in 0..<4 { add(longAgo, .cleaned, daysAgo: 300 - n * 50) }
        add(longAgo, .skipped, daysAgo: 100)
        let yearly = stats().frequentSkippers()
        check("skips older than a year are forgotten (1 skip inside the year)", !listed(yearly, longAgo))
        let ninety = synthetic("ST two in a year"); add(ninety, .cleaned, daysAgo: 330); add(ninety, .skipped, daysAgo: 250); add(ninety, .cleaned, daysAgo: 200); add(ninety, .cleaned, daysAgo: 150)
        add(ninety, .cleaned, daysAgo: 110); add(ninety, .cleaned, daysAgo: 80); add(ninety, .cleaned, daysAgo: 50); add(ninety, .skipped, daysAgo: 20)
        check("two skips spread over the year are flagged (more than 6 visits apart)", listed(stats().frequentSkippers(), ninety))
        context.delete(longAgo); context.delete(ninety)

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

        // price rise: due when no rise for the set time, or no date logged
        let riser = synthetic("ST riser", price: 15)
        let recent = synthetic("ST recent", price: 20); recent.priceSince = RoundCalendar.london.date(byAdding: .month, value: -6, to: today)
        let brandNew = synthetic("ST brand new", price: 20); brandNew.priceSince = RoundCalendar.london.date(byAdding: .month, value: -30, to: today)
        let dueNow = stats().risesDue()
        check("a customer with no price date is due a rise", dueNow.contains { $0 === riser })
        check("a price changed 6 months ago isn't due", !dueNow.contains { $0 === recent })
        check("a price unchanged for 30 months is due", dueNow.contains { $0 === brandNew })

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

        // projected Next Up plan
        do {
            let planCrews = try context.fetch(FetchDescriptor<Crew>())
            let planDiary = try context.fetch(FetchDescriptor<WorkDay>())
            let planSettings = try context.fetch(FetchDescriptor<AppSettings>()).first
            let allNow = try context.fetch(FetchDescriptor<Customer>(sortBy: [SortDescriptor(\.sequence)]))
            let planned = RoundPlanner.plan(customers: allNow, settings: planSettings, crews: planCrews, workDays: planDiary, today: today)
            let placed = planned.days.flatMap(\.customers) + planned.later
            let shownIDs = planned.days.flatMap(\.rows).map(\.customer.id)
            check("plan: nobody appears twice", Set(shownIDs).count == shownIDs.count && Set(placed.map(\.id)).count == placed.count)
            var reachesTarget = true, overTarget = true
            for day in planned.days.dropLast() where !day.customers.isEmpty && day.bookedCount == 0 {
                if day.total + day.doneTotal < day.target { reachesTarget = false }
                if day.total + day.doneTotal > day.target * Decimal(1.2) + 50 { overTarget = false }
            }
            check("plan: every full day reaches its target", reachesTarget)
            check("plan: no day goes far over (keeping a cluster whole allows up to about 20% over)", overTarget)
            var pendingSeen: [UUID: Int] = [:]
            var pendingCounted = false, totalsMatch = true
            for day in planned.days {
                for row in day.rows where row.state == .notStarted {
                    pendingSeen[row.customer.id, default: 0] += 1
                    if day.customers.contains(where: { $0.id == row.customer.id }) { pendingCounted = true }
                }
                if day.total != day.customers.reduce(Decimal(0), { $0 + $1.price }) { totalsMatch = false }
            }
            let notStartedCount = allNow.filter { $0.status == .notStarted }.count
            check("plan: each not-started customer shows once, greyed", pendingSeen.count == notStartedCount && pendingSeen.values.allSatisfy { $0 == 1 }, "\(pendingSeen.count) of \(notStartedCount)")
            check("plan: greyed customers aren't counted in a day's total", !pendingCounted && totalsMatch)
            let eoOff = planned.days.flatMap(\.rows).filter { $0.state == .everyOtherOff }
            check("plan: every-other customers on their off round are greyed, never counted", eoOff.allSatisfy { row in !planned.days.contains { $0.customers.contains { $0 === row.customer } } })

            // Rows keep round order within the lap (sequence goes up, wrapping once at most per day).
            var wraps = 0
            for day in planned.days {
                let seqs = day.rows.map(\.customer).filter { !$0.name.hasPrefix("ST ") && !$0.name.hasPrefix("Self Test") }.map(\.sequence)
                for (x, y) in zip(seqs, seqs.dropFirst()) where y < x { wraps += 1 }
            }
            check("plan: round order is kept (wraps round at most once)", wraps <= 1, "\(wraps) wraps")

            // Every-other: replay the history and see how often the rule matches what was actually logged.
            let lap = planned.lapDays
            var bestFactor = 1.5, bestScore = -1.0, scoreAt15 = 0.0, cases = 0
            for factor in stride(from: 1.2, through: 1.8, by: 0.1) {
                var right = 0, total = 0
                for customer in allNow where customer.everyOther {
                    let visits = customer.allVisits.filter { $0.kind == .cleaned || $0.kind == .notDue }.sorted { $0.date < $1.date }
                    var lastClean: Date?
                    for visit in visits {
                        if let lastClean {
                            let gap = RoundCalendar.london.dateComponents([.day], from: lastClean, to: visit.date).day ?? 0
                            let predictedOff = Double(gap) < Double(lap) * factor
                            total += 1
                            if predictedOff == (visit.kind == .notDue) { right += 1 }
                        }
                        if visit.kind == .cleaned { lastClean = visit.date }
                    }
                }
                let score = total == 0 ? 1 : Double(right) / Double(total)
                if abs(factor - 1.5) < 0.01 { scoreAt15 = score; cases = total }
                if score > bestScore { bestScore = score; bestFactor = factor }
            }
            lines.append("EOBACKTEST lap \(lap) days, factor 1.5 right \(Int(scoreAt15 * 100))% of \(cases), best factor \(String(format: "%.1f", bestFactor)) at \(Int(bestScore * 100))%")
            check("every-other rule matches the logged history at least 90% of the time", scoreAt15 >= 0.9, "\(Int(scoreAt15 * 100))%")
            for day in planned.days.prefix(14) {
                lines.append("PLANDAY \(RoundCalendar.dayString(day.date)) to do \(day.customers.count) £\(day.total) done £\(day.doneTotal) rows \(day.rows.count)")
            }
        }

        // Day one replay: Mon 12 Oct 2026, the visits logged on the phone, in an out-of-order sequence.
        do {
            let replayDay = RoundCalendar.date(year: 2026, month: 10, day: 12)
            let people = try context.fetch(FetchDescriptor<Customer>(sortBy: [SortDescriptor(\.sequence)])).filter { !$0.name.hasPrefix("ST ") && !$0.name.hasPrefix("Self Test") }
            let replaySettings = try context.fetch(FetchDescriptor<AppSettings>()).first
            let replayCrews = try context.fetch(FetchDescriptor<Crew>())
            let replayDiary = try context.fetch(FetchDescriptor<WorkDay>())
            func replayPlan() -> RoundPlanner.Plan { RoundPlanner.plan(customers: people, settings: replaySettings, crews: replayCrews, workDays: replayDiary, today: replayDay) }
            let start = replayPlan()
            if let monday = start.days.first, monday.date == replayDay {
                let booked = monday.customers
                for customer in booked { customer.bookedFor = replayDay }
                let bookedIDs = Set(booked.map(\.id))
                let tuesdayBefore = Set(start.days.dropFirst().first?.customers.map(\.id) ?? [])
                // (sequence, what happened) in the order replayed
                let steps: [(String, VisitLogger.Action)] = [
                    ("Andrew Wiseman", .cleanedExtra(extra: 28, note: "Full clean", paid: false)), ("Al/Sue", .cleanedPaid), ("Clare Ryder", .cleanedNotPaid),
                    ("Paul and Nicki Lawrence", .cleanedPaid), ("Anne Smith", .cleanedPaid), ("Barbara Evans", .cleanedPaid), ("Sarah Williams", .cleanedNotPaid),
                    ("Gordon", .cleanedPaid), ("Lyn Garage", .cleanedNotPaid), ("Olga & Irfon", .cleanedNotPaid), ("Cherry Russell", .notDue),
                    ("Louise (C Jones)", .notDue), ("Val Loftus", .cleanedNotPaid), ("Caroline Brine", .cleanedNotPaid), ("Ian Paddy (Parry)", .cleanedPaid),
                    ("P A & Lorna Roberts", .cleanedNotPaid), ("Linda Knight", .cleanedNotPaid), ("Rachel Huws", .cleanedNotPaid),
                    ("Glenis Butler", .cleanedExtra(extra: 3, note: nil, paid: true)), ("Tracey Owen", .cleanedNotPaid), ("Ira & Hillary Philip", .cleanedPaid),
                    ("Alan McAdams", .cleanedNotPaid), ("Nia Corcoran", .skipped), ("Darren Jarvis", .cleanedNotPaid),
                ]
                var undos: [() -> Void] = []
                var doneShownAsToDo = 0, bookedLeftMonday = 0, jumpedToEnd = 0
                var doneSoFar = Set<UUID>()
                for (name, action) in steps {
                    guard let customer = people.first(where: { $0.name.trimmingCharacters(in: .whitespaces) == name && $0.status != .cancelled }) else {
                        lines.append("DAYONE missing \(name)"); continue
                    }
                    undos.append(VisitLogger.perform(action, for: customer, on: replayDay, in: context))
                    doneSoFar.insert(customer.id)
                    let now = replayPlan()
                    let toDo = Set(now.days.flatMap(\.customers).map(\.id) + now.later.map(\.id))
                    doneShownAsToDo += doneSoFar.intersection(toDo).count
                    let mondayNow = Set(now.days.first?.rows.map(\.customer.id) ?? [])
                    bookedLeftMonday += bookedIDs.subtracting(mondayNow).count
                    let early = Set(now.days.prefix(3).flatMap(\.rows).map(\.customer.id))
                    jumpedToEnd += tuesdayBefore.subtracting(early).subtracting(doneSoFar).count
                }
                let end = replayPlan()
                let monday = end.days.first
                lines.append("DAYONE done £\(monday?.doneTotal ?? 0) left £\(monday?.total ?? 0) rows \(monday?.rows.count ?? 0)")
                check("day one: nobody cleaned today ever shows again as still to do", doneShownAsToDo == 0, "\(doneShownAsToDo)")
                check("day one: booked customers never leave Monday", bookedLeftMonday == 0, "\(bookedLeftMonday)")
                check("day one: cleaning out of order never sends Tuesday's customers to the end", jumpedToEnd == 0, "\(jumpedToEnd)")
                check("day one: Monday's done total matches the phone (£414)", (monday?.doneTotal ?? 0) - (start.days.first?.doneTotal ?? 0) == 414, "£\((monday?.doneTotal ?? 0) - (start.days.first?.doneTotal ?? 0))")
                check("day one: EOs logged not due and Nia's skip stay on Monday, not counted",
                      ["Cherry Russell", "Louise (C Jones)", "Nia Corcoran"].allSatisfy { name in monday?.rows.contains { $0.customer.name == name && $0.isDone && !$0.state.counts } ?? false })
                for undo in undos.reversed() { undo() }
                for customer in booked { customer.bookedFor = nil }
            } else {
                check("day one: Monday 12 Oct is a working day in the plan", false)
            }
        }

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

        // day messages
        do {
            let today0 = RoundCalendar.date(year: 2026, month: 10, day: 12)   // a Monday
            let tomorrow = RoundCalendar.date(year: 2026, month: 10, day: 13)
            let thursday = RoundCalendar.date(year: 2026, month: 10, day: 15)
            check("standard message has the full date", DayMessage.text(template: DayMessage.defaultTemplate, name: "Ann", date: tomorrow, today: today0) == "Hi Ann, we're planning to clean your windows on Tuesday 13 October. Let us know if that doesn't suit!")
            check("message can still say tomorrow", DayMessage.text(template: "{name}: {when}", name: "Ann", date: tomorrow, today: today0) == "Ann: tomorrow")
            check("message names a later day", DayMessage.when(thursday, today: today0) == "on Thursday" && DayMessage.when(today0, today: today0) == "today")
            let link = DayMessage.whatsAppURL(digits: "447700900123", text: "Hi Ann & Bob")?.absoluteString ?? ""
            check("WhatsApp link has the number and an encoded message", link.hasPrefix("https://wa.me/447700900123?text=Hi%20Ann") && link.contains("%26") )
            check("no number means no link", DayMessage.whatsAppURL(digits: "", text: "x") == nil)
        }

        // round sheet cells
        do {
            let sheetPeople = try context.fetch(FetchDescriptor<Customer>(sortBy: [SortDescriptor(\.sequence)]))
            var rounds: [String: [Customer]] = [:]
            for person in sheetPeople where !person.round.isEmpty && person.status != .cancelled { rounds[person.round, default: []].append(person) }
            var allShown = true, datesOK = true, tight = 0, pairs = 0
            for (_, people) in rounds {
                let layout = RoundSheet.layout(for: people)
                let columns = layout.columns + 1
                var previous: [RoundSheet.Cell?]?
                for person in people {
                    let cells = RoundSheet.cells(for: person, layout: layout, columns: columns)
                    let shown = cells.compactMap { $0 }
                    if shown.count != person.allVisits.count { allShown = false }
                    if shown.filter({ $0.date != "—" }).count != person.allVisits.filter({ $0.kind == .cleaned }).count { datesOK = false }
                    // Neighbours' cleans in the same column should be from about the same time.
                    if let previous {
                        for (a, b) in zip(previous, cells) {
                            if let a, let b, a.kind != .skipped, a.kind != .notDue, b.kind != .skipped, b.kind != .notDue {
                                pairs += 1
                                if abs(a.when.timeIntervalSince(b.when)) < 45 * 86_400 { tight += 1 }
                            }
                        }
                    }
                    previous = cells
                }
            }
            check("round sheet shows every visit exactly once", allShown)
            check("a date shows for every clean, a dash for skips and not-dues", datesOK)
            check("neighbours' cleans in the same column are from the same time round", pairs > 0 && Double(tight) / Double(pairs) > 0.97, "\(tight) of \(pairs)")
            if let ira = sheetPeople.first(where: { $0.name.hasPrefix("Ira & Hillary") }), let lyn = sheetPeople.first(where: { $0.name == "Lyn Garage" }), let people = rounds[ira.round] {
                let layout = RoundSheet.layout(for: people)
                let columns = layout.columns + 1
                let iraCells = RoundSheet.cells(for: ira, layout: layout, columns: columns)
                let lynCells = RoundSheet.cells(for: lyn, layout: layout, columns: columns)
                let column = iraCells.firstIndex { $0 != nil }
                check("a late joiner's first clean sits in the same column as everyone's clean of that date", column != nil && lynCells[column!]?.date == iraCells[column!]?.date)
            }
        }

        // automatic daily backups
        do {
            let folder = URL.temporaryDirectory.appendingPathComponent("autobackup-test-\(UUID().uuidString)", isDirectory: true)
            let testDefaults = UserDefaults(suiteName: "autobackup-test")!
            testDefaults.removePersistentDomain(forName: "autobackup-test")
            let day0 = RoundCalendar.date(year: 2027, month: 1, day: 1)
            var written: URL?
            for offset in 0..<17 {
                let day = RoundCalendar.london.date(byAdding: .day, value: offset, to: day0)!
                written = AutoBackup.run(context: context, directory: folder, now: day, defaults: testDefaults)
            }
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            check("daily backup keeps only the newest 14", files.count == AutoBackup.keepDays, "\(files.count) files")
            let newest = files.map(\.lastPathComponent).sorted().last
            check("daily backups are named by date", newest == "splash-out-daily-2027-01-17.json", newest ?? "none")
            if let written, let data = try? Data(contentsOf: written), let decoded = try? RoundFile.decode(data) {
                check("a daily backup holds every customer and can be read back", decoded.customers.count == (try context.fetchCount(FetchDescriptor<Customer>())))
            } else {
                check("a daily backup holds every customer and can be read back", false)
            }
            let empty = try ModelContainer(for: Persistence.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let emptyFolder = URL.temporaryDirectory.appendingPathComponent("autobackup-empty-\(UUID().uuidString)", isDirectory: true)
            check("an empty app never writes a backup", AutoBackup.run(context: empty.mainContext, directory: emptyFolder, defaults: testDefaults) == nil && !FileManager.default.fileExists(atPath: emptyFolder.path))
            // a chosen folder gets each day's copy too
            let chosen = URL.temporaryDirectory.appendingPathComponent("autobackup-chosen-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
            try AutoBackup.setFolder(chosen, defaults: testDefaults)
            let local = URL.temporaryDirectory.appendingPathComponent("autobackup-local-\(UUID().uuidString)", isDirectory: true)
            for offset in 0..<33 {
                let day = RoundCalendar.london.date(byAdding: .day, value: offset, to: day0)!
                _ = AutoBackup.run(context: context, directory: local, now: day, defaults: testDefaults)
            }
            let copies = ((try? FileManager.default.contentsOfDirectory(at: chosen, includingPropertiesForKeys: nil)) ?? []).map(\.lastPathComponent).sorted()
            check("each day's backup is also copied into the chosen folder", copies.last == "splash-out-daily-2027-02-02.json", copies.last ?? "none")
            check("the chosen folder keeps only the newest 30", copies.count == AutoBackup.keepInFolder, "\(copies.count)")
            check("a working folder is reported as working", AutoBackup.folderWorks(defaults: testDefaults))
            try? FileManager.default.removeItem(at: chosen)
            for offset in 33..<34 { _ = AutoBackup.run(context: context, directory: local, now: RoundCalendar.london.date(byAdding: .day, value: offset, to: day0)!, defaults: testDefaults) }
            check("a folder that has gone away is reported, without stopping the backup", !AutoBackup.folderWorks(defaults: testDefaults) && !(testDefaults.string(forKey: AutoBackup.folderErrorKey) ?? "").isEmpty)
            try? FileManager.default.removeItem(at: local)
            try? FileManager.default.removeItem(at: folder)
        }

        // money is never rounded away on screen
        do {
            func shown(_ value: Decimal) -> String { value.pounds }
            check("whole pounds show without pence", shown(1140) == "£1,140")
            check("pence are kept, not rounded", shown(Decimal(string: "1139.5")!) == "£1,139.50" && shown(Decimal(string: "16.05")!) == "£16.05")
        }

        // calendar contents
        do {
            let calSettings = try context.fetch(FetchDescriptor<AppSettings>()).first!
            let calCrews = try context.fetch(FetchDescriptor<Crew>())
            let calDiary = try context.fetch(FetchDescriptor<WorkDay>())
            let start = RoundCalendar.date(year: 2027, month: 1, day: 4)   // a Monday
            let plain = CalendarPlan.entries(settings: calSettings, crews: calCrews, workDays: [], from: start, days: 14)
            let usual = calSettings.usualWeek
            let workingPerWeek = usual.prefix(7).filter { !$0.isEmpty }.count
            check("calendar has one entry per usual working day", plain.count == workingPerWeek * 2, "\(plain.count) vs \(workingPerWeek * 2)")
            check("calendar entries are crew names only, no money", plain.values.allSatisfy { title in !title.contains("£") && calCrews.contains { $0.name == title } })
            let off = WorkDay(date: start, dayOff: true, crewMembers: [], note: "Dentist")
            let withOff = CalendarPlan.entries(settings: calSettings, crews: calCrews, workDays: [off], from: start, days: 14)
            check("a day off shows as Day off, without its note", withOff[start] == "Day off" && !withOff.values.contains { $0.contains("Dentist") })
            let extra = calCrews.first { $0.name != usual[0] } ?? calCrews[0]
            let swapped = WorkDay(date: start, dayOff: false, crewMembers: extra.members, note: nil)
            let withSwap = CalendarPlan.entries(settings: calSettings, crews: calCrews, workDays: [swapped], from: start, days: 14)
            check("a different crew in the diary shows that crew", withSwap[start] == extra.name)
            _ = calDiary
        }

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
        let anonymous = try String(contentsOf: DataExports.analysisReport(includeNames: false, includeNotes: false, context: context), encoding: .utf8)
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
        let withNotes = try String(contentsOf: DataExports.analysisReport(includeNames: false, includeNotes: true, context: context), encoding: .utf8)
        let withoutNotes = try String(contentsOf: DataExports.analysisReport(includeNames: false, includeNotes: false, context: context), encoding: .utf8)
        check("analysis report includes notes when asked", longNote.map { withNotes.contains($0) && named.contains($0) } ?? true)
        check("analysis report leaves notes out when switched off", longNote.map { !withoutNotes.contains($0) } ?? true)

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
