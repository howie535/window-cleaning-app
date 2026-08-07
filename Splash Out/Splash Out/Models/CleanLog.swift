import Foundation
import SwiftData

@Model
final class CleanLog {
    var date: Date
    var amountCharged: Decimal
    var amountPaid: Decimal
    var notes: String
    var customer: Customer?

    init(date: Date, amountCharged: Decimal, amountPaid: Decimal, notes: String, customer: Customer? = nil) {
        self.date = date
        self.amountCharged = amountCharged
        self.amountPaid = amountPaid
        self.notes = notes
        self.customer = customer
    }

    /// Positive when the customer paid more than charged, negative when they paid less.
    var paymentDifference: Decimal {
        amountPaid - amountCharged
    }
}
