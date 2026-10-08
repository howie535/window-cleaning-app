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

        lines.append(failures == 0 ? "SELFTEST: ALL \(lines.count) CHECKS PASSED" : "SELFTEST: \(failures) FAILED")
        return lines.joined(separator: "\n")
    }
}
#endif
