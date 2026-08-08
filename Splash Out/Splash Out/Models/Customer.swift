import CoreLocation
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
    var latitude: Double?
    var longitude: Double?

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

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
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

    /// International-format digits, required by WhatsApp's wa.me link (country code, no leading 0).
    var whatsAppDigits: String {
        UKPhoneNumber.toWhatsAppDigits(phone)
    }

    /// Running total of over/underpayment across all logged cleans. Positive means the customer
    /// is in credit (they've paid more than charged overall); negative means they owe money.
    var outstandingBalance: Decimal {
        cleanLogs.reduce(0) { $0 + $1.paymentDifference }
    }

    /// The regular price adjusted to claw back a credit or recoup a shortfall from past cleans.
    var suggestedNextPrice: Decimal {
        max(0, price - outstandingBalance)
    }
}
