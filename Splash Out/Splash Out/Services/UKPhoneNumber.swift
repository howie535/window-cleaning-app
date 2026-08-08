import Foundation

/// Numbers are stored and displayed in UK national format (leading 0, e.g. "07700 900123"),
/// since that's what customers give you. WhatsApp's wa.me links need international format
/// instead, so that conversion happens only at the point of building the link.
enum UKPhoneNumber {
    static func toNationalFormat(_ raw: String) -> String {
        var digits = raw.filter(\.isNumber)
        if digits.hasPrefix("44") {
            digits = "0" + digits.dropFirst(2)
        }
        return digits
    }

    static func toWhatsAppDigits(_ raw: String) -> String {
        var digits = raw.filter(\.isNumber)
        if digits.hasPrefix("0") {
            digits = "44" + digits.dropFirst()
        }
        return digits
    }
}
