import CoreLocation
import Foundation
import SwiftData

// CloudKit-compatible: every property has a default or is optional, no unique constraints,
// relationships are optional with inverses.
@Model
final class Customer {
    var id: UUID = UUID()
    /// Position in round order (the "conveyor belt").
    var sequence: Int = 0
    var round: String = ""
    var area: String = ""
    var statusRaw: String = CustomerStatus.active.rawValue
    var name: String = ""
    var address: String = ""
    var phone: String = ""
    var price: Decimal = 0
    var priceSince: Date?
    var everyOther: Bool = false
    var frontOnly: Bool = false
    var contactRaw: String = ContactMethod.whatsapp.rawValue
    var payMethodRaw: String?
    var notes: [String] = []
    var latitude: Double?
    var longitude: Double?

    @Relationship(deleteRule: .cascade, inverse: \Visit.customer)
    var visits: [Visit]? = []

    @Relationship(deleteRule: .cascade, inverse: \PriceChange.customer)
    var priceChanges: [PriceChange]? = []

    init(
        name: String,
        address: String = "",
        phone: String = "",
        price: Decimal = 0,
        sequence: Int = 0,
        round: String = "",
        area: String = "",
        status: CustomerStatus = .active,
        notes: [String] = []
    ) {
        self.name = name
        self.address = address
        self.phone = phone
        self.price = price
        self.sequence = sequence
        self.round = round
        self.area = area
        self.statusRaw = status.rawValue
        self.notes = notes
    }

    var status: CustomerStatus {
        get { CustomerStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var contact: ContactMethod {
        get { ContactMethod(rawValue: contactRaw) ?? .whatsapp }
        set { contactRaw = newValue.rawValue }
    }

    var payMethod: PayMethod? {
        get { payMethodRaw.flatMap(PayMethod.init(rawValue:)) }
        set { payMethodRaw = newValue?.rawValue }
    }

    var allVisits: [Visit] { visits ?? [] }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var lastCleanDate: Date? {
        allVisits.filter { $0.kind == .cleaned }.map(\.date).max()
    }

    /// Notes as one block of text, for editing.
    var notesText: String {
        get { notes.joined(separator: "\n") }
        set { notes = newValue.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) }
    }

    /// International-format digits, required by WhatsApp's wa.me link (country code, no leading 0).
    var whatsAppDigits: String {
        UKPhoneNumber.toWhatsAppDigits(phone)
    }

    /// Running total of over/underpayment across cleans that have actually been paid.
    /// Positive: the customer is in credit. Negative: they've underpaid.
    /// Unpaid cleans (paid == 0) are deliberately excluded: those are "money owed", handled separately.
    var outstandingBalance: Decimal {
        allVisits
            .filter { $0.kind == .cleaned && $0.paid > 0 }
            .reduce(0) { $0 + $1.paymentDifference }
    }

    /// The regular price adjusted to claw back a credit or recoup a shortfall from past cleans.
    var suggestedNextPrice: Decimal {
        max(0, price - outstandingBalance)
    }
}
