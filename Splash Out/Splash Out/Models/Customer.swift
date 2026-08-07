import Foundation
import SwiftData

@Model
final class Customer {
    var name: String
    var address: String
    var phone: String
    var price: Decimal
    var frequencyWeeks: Int
    var accessNotes: String

    @Relationship(deleteRule: .cascade, inverse: \CleanLog.customer)
    var cleanLogs: [CleanLog] = []

    init(
        name: String,
        address: String,
        phone: String,
        price: Decimal,
        frequencyWeeks: Int,
        accessNotes: String
    ) {
        self.name = name
        self.address = address
        self.phone = phone
        self.price = price
        self.frequencyWeeks = frequencyWeeks
        self.accessNotes = accessNotes
    }

    var lastCleanDate: Date? {
        cleanLogs.map(\.date).max()
    }

    var nextDueDate: Date? {
        guard let lastCleanDate else { return nil }
        return Calendar.current.date(byAdding: .weekOfYear, value: frequencyWeeks, to: lastCleanDate)
    }

    var isDue: Bool {
        guard let nextDueDate else { return true }
        return nextDueDate <= Date()
    }

    /// Digits-only phone number, required by WhatsApp's wa.me link format (country code + number, no symbols).
    var whatsAppDigits: String {
        phone.filter(\.isNumber)
    }
}
