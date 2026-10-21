import Foundation
import SwiftData
import SwiftUI

/// The one-tap logging actions from Docs/SPEC.md section 3, plus recording payments.
/// Every action returns what's needed to undo it.
@MainActor
enum VisitLogger {
    enum Action {
        case cleanedPaid
        case cleanedNotPaid
        /// Extra (or less, if negative) on top of the usual charge, e.g. conservatory roof or front only.
        case cleanedExtra(extra: Decimal, note: String?, paid: Bool)
        /// Cleaned at a chosen list price (for customers with two prices).
        case cleanedAt(price: Decimal, paid: Bool)
        /// Front only, at an amount given each time.
        case frontOnly(price: Decimal, paid: Bool)
        case skipped
        case notDue

        var summary: String {
            switch self {
            case .cleanedPaid: "cleaned and paid"
            case .cleanedNotPaid: "cleaned, not paid"
            case .cleanedExtra: "cleaned with extra"
            case .cleanedAt(_, let paid): paid ? "cleaned and paid" : "cleaned, not paid"
            case .frontOnly(_, let paid): paid ? "front only, paid" : "front only, not paid"
            case .skipped: "skipped"
            case .notDue: "not due"
            }
        }
    }

    @discardableResult
    static func perform(_ action: Action, for customer: Customer, on date: Date = Date(), in context: ModelContext) -> () -> Void {
        let day = RoundCalendar.startOfDay(date)
        let previousStatus = customer.status
        let previousBooking = customer.bookedFor

        let visit: Visit
        switch action {
        case .cleanedPaid:
            visit = cleaned(customer, day: day, base: customer.nextListPrice, extra: 0, note: nil, paid: true)
        case .cleanedNotPaid:
            visit = cleaned(customer, day: day, base: customer.nextListPrice, extra: 0, note: nil, paid: false)
        case .cleanedExtra(let extra, let note, let paid):
            visit = cleaned(customer, day: day, base: customer.price, extra: extra, note: note, paid: paid)
        case .cleanedAt(let price, let paid):
            visit = cleaned(customer, day: day, base: price, extra: 0, note: nil, paid: paid)
        case .frontOnly(let price, let paid):
            visit = cleaned(customer, day: day, base: price, extra: 0, note: frontOnlyNote, paid: paid)
        case .skipped:
            visit = Visit(date: day, kind: .skipped, listPrice: customer.price, charged: 0)
        case .notDue:
            visit = Visit(date: day, kind: .notDue, listPrice: customer.price, charged: 0)
        }

        context.insert(visit)
        visit.customer = customer
        customer.bookedFor = nil

        // "not_started until their first clean"
        if visit.kind == .cleaned && customer.status == .notStarted {
            customer.status = .active
        }

        return { [weak customer] in
            if let customer, customer.status != previousStatus { customer.status = previousStatus }
            customer?.bookedFor = previousBooking
            remove(visit, in: context)
        }
    }

    /// A custom clean (any date or amount), from the full form.
    @discardableResult
    static func logCustomClean(
        for customer: Customer,
        date: Date,
        charged: Decimal,
        paid: Decimal,
        note: String?,
        in context: ModelContext
    ) -> () -> Void {
        let day = RoundCalendar.startOfDay(date)
        let previousStatus = customer.status
        let previousBooking = customer.bookedFor
        let suggested = customer.suggestedNextPrice
        let visit = Visit(
            date: day,
            kind: .cleaned,
            listPrice: customer.price,
            charged: charged,
            paid: paid,
            paidDate: paid > 0 ? day : nil,
            note: note,
            // Only counts as using up credit/debt when the usual adjusted price was charged.
            creditApplied: charged == suggested ? customer.price - suggested : 0
        )
        context.insert(visit)
        visit.customer = customer
        customer.bookedFor = nil
        if customer.status == .notStarted { customer.status = .active }
        return { [weak customer] in
            if let customer, customer.status != previousStatus { customer.status = previousStatus }
            customer?.bookedFor = previousBooking
            remove(visit, in: context)
        }
    }

    static let frontOnlyNote = "Front only"

    /// What they were charged for their last front-only clean, to start from next time.
    static func lastFrontOnlyPrice(for customer: Customer) -> Decimal? {
        customer.allVisits.filter { $0.kind == .cleaned && $0.note == frontOnlyNote }.max { $0.date < $1.date }?.listPrice
    }

    /// Runs `work` once a swipe or sheet animation has finished (about a third of a second), so the screens updating
    /// for the new visit never stall the animation.
    static func afterAnimation(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation { work() }
        }
    }

    /// A paid clean that also settles everything they owed from earlier cleans. One undo reverses both.
    static func cleanAndPayOff(_ action: Action, for customer: Customer, in context: ModelContext) -> (undo: () -> Void, paidOff: Decimal) {
        let earlier = unpaidVisits(for: customer)
        let amount = earlier.reduce(Decimal(0)) { $0 + $1.charged - $1.paid }
        let undoClean = perform(action, for: customer, in: context)
        let payment = recordPayment(amount, across: earlier)
        return ({ payment.undo(); undoClean() }, amount)
    }

    /// Deletes a visit and takes it off its customer straight away, so lists and totals update at once.
    static func remove(_ visit: Visit, in context: ModelContext) {
        visit.customer?.visits?.removeAll { $0 === visit }
        context.delete(visit)
        try? context.save()
    }

    /// A clean at `base` (the usual or second price) plus `extra`, with any credit or shortfall netted in.
    private static func cleaned(_ customer: Customer, day: Date, base: Decimal, extra: Decimal, note: String?, paid: Bool) -> Visit {
        let suggested = max(0, base - customer.outstandingBalance)
        let charged = max(0, suggested + extra)
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Visit(
            date: day,
            kind: .cleaned,
            listPrice: base,
            charged: charged,
            paid: paid ? charged : 0,
            paidDate: paid ? day : nil,
            note: (trimmed?.isEmpty ?? true) ? nil : trimmed,
            creditApplied: base - suggested
        )
    }

    // MARK: Payments

    /// What is still owed on a customer's visits, oldest first.
    static func unpaidVisits(for customer: Customer) -> [Visit] {
        customer.allVisits.filter(\.isUnpaid).sorted { $0.date < $1.date }
    }

    /// Pays `amount` across `visits` (oldest first). Returns the undo, and any money left over.
    static func recordPayment(
        _ amount: Decimal,
        across visits: [Visit],
        on date: Date = Date(),
        creditTo creditTarget: Visit? = nil
    ) -> (undo: () -> Void, leftover: Decimal) {
        let day = RoundCalendar.startOfDay(date)
        let ordered = visits.sorted { $0.date < $1.date }
        let result = PaymentAllocator.allocate(amount, owed: ordered.map { $0.charged - $0.paid })

        // Anything over what's owed is kept as credit on the newest clean (paid more than charged), which
        // Customer.outstandingBalance picks up and takes off their next clean. Work done isn't changed by it.
        let creditVisit = ordered.last ?? creditTarget
        var all = ordered
        if let creditVisit, !all.contains(where: { $0 === creditVisit }) { all.append(creditVisit) }

        // Snapshot for undo.
        let before = all.map { (visit: $0, paid: $0.paid, paidDate: $0.paidDate) }

        for (visit, share) in zip(ordered, result.allocations) where share > 0 {
            visit.paid += share
            if visit.paid >= visit.charged { visit.paidDate = day }
        }
        var leftover = result.leftover
        if leftover > 0, let creditVisit {
            creditVisit.paid += leftover
            creditVisit.paidDate = day
            leftover = 0
        }

        let undo = {
            for entry in before {
                entry.visit.paid = entry.paid
                entry.visit.paidDate = entry.paidDate
            }
        }
        return (undo, leftover)
    }
}

/// New customers can go anywhere in round order, not just the end.
enum RoundOrder {
    /// Gives `customer` the position just after `after` (or the end if nil), shifting later customers down one.
    @MainActor
    static func place(_ customer: Customer, after: Customer?, among all: [Customer]) {
        let others = all.filter { $0 !== customer }
        guard let after else {
            customer.sequence = (others.map(\.sequence).max() ?? 0) + 1
            return
        }
        for other in others where other.sequence > after.sequence {
            other.sequence += 1
        }
        customer.sequence = after.sequence + 1
    }
}

extension RoundOrder {
    /// Moves customers within the full round (as list offsets, like SwiftUI's onMove) and renumbers everyone 1...n.
    @MainActor
    static func move(_ ordered: [Customer], from offsets: IndexSet, to destination: Int) {
        var list = ordered
        list.move(fromOffsets: offsets, toOffset: destination)
        for (index, customer) in list.enumerated() where customer.sequence != index + 1 {
            customer.sequence = index + 1
        }
    }
}

/// Search and filters for the Customers screen (Docs/SPEC.md section 5).
enum CustomerFilter {
    struct Criteria: Equatable {
        var search = ""
        var round: String?
        var area: String?
        var status: CustomerStatus?
        var isActive: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty || round != nil || area != nil || status != nil }
    }

    @MainActor
    static func apply(_ criteria: Criteria, to customers: [Customer]) -> [Customer] {
        let term = criteria.search.trimmingCharacters(in: .whitespaces)
        return customers.filter { customer in
            if let round = criteria.round, customer.round != round { return false }
            if let area = criteria.area, customer.area != area { return false }
            if let status = criteria.status, customer.status != status { return false }
            guard !term.isEmpty else { return true }
            return customer.name.localizedCaseInsensitiveContains(term)
                || customer.address.localizedCaseInsensitiveContains(term)
                || customer.area.localizedCaseInsensitiveContains(term)
                || customer.round.localizedCaseInsensitiveContains(term)
                || customer.notes.contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }
}
