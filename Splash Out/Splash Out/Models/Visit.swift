import Foundation
import SwiftData

@Model
final class Visit {
    var date: Date = Date()
    var kindRaw: String = VisitKind.cleaned.rawValue
    /// The customer's price on that date.
    var listPrice: Decimal = 0
    /// What the clean is worth. Normally listPrice; more for extras, less for front only.
    var charged: Decimal = 0
    /// 0 until paid.
    var paid: Decimal = 0
    var paidDate: Date?
    var note: String?
    /// Customer credit (+) or debt (-) netted into this charge: listPrice minus the suggested price used.
    /// Lets the running balance use up a credit once it has been taken off a charge.
    var creditApplied: Decimal = 0
    /// Skipped / not-due dates in the workbook are estimates (it only recorded a dash).
    var dateEstimated: Bool = false
    var customer: Customer?

    init(
        date: Date,
        kind: VisitKind = .cleaned,
        listPrice: Decimal,
        charged: Decimal,
        paid: Decimal = 0,
        paidDate: Date? = nil,
        note: String? = nil,
        dateEstimated: Bool = false,
        creditApplied: Decimal = 0,
        customer: Customer? = nil
    ) {
        self.date = date
        self.kindRaw = kind.rawValue
        self.listPrice = listPrice
        self.charged = charged
        self.paid = paid
        self.paidDate = paidDate
        self.note = note
        self.dateEstimated = dateEstimated
        self.creditApplied = creditApplied
        self.customer = customer
    }

    var kind: VisitKind {
        get { VisitKind(rawValue: kindRaw) ?? .cleaned }
        set { kindRaw = newValue.rawValue }
    }

    /// Unpaid when it was cleaned and the payment hasn't covered the charge.
    var isUnpaid: Bool {
        kind == .cleaned && paid < charged
    }

    /// Positive when the customer paid more than charged, negative when less.
    var paymentDifference: Decimal {
        paid - charged
    }

    /// What this visit adds to the customer's running balance (see Customer.outstandingBalance).
    var balanceEffect: Decimal {
        paid - charged - creditApplied
    }
}
