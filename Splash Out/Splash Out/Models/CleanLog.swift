import Foundation
import SwiftData

@Model
final class CleanLog {
    var date: Date
    var amountCharged: Decimal
    var paid: Bool
    var notes: String
    var customer: Customer?

    init(date: Date, amountCharged: Decimal, paid: Bool, notes: String, customer: Customer? = nil) {
        self.date = date
        self.amountCharged = amountCharged
        self.paid = paid
        self.notes = notes
        self.customer = customer
    }
}
