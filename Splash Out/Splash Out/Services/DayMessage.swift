import Foundation

/// The WhatsApp message for a day's customers, and the link that opens it.
enum DayMessage {
    static let defaultTemplate = "Hi {name}, we're planning to clean your windows {when}. Let us know if that doesn't suit!"
    static let templateKey = "whatsapp.dayTemplate"

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = RoundCalendar.london.timeZone
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    /// "today", "tomorrow", or "on Tuesday" (with the date if it's more than a week away).
    static func when(_ date: Date, today: Date = RoundCalendar.startOfDay()) -> String {
        let days = RoundCalendar.london.dateComponents([.day], from: today, to: date).day ?? 0
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case 2...6: return "on \(dayFormatter.string(from: date))"
        default: return "on \(dayFormatter.string(from: date)) \(RoundCalendar.short(date))"
        }
    }

    static func text(template: String, name: String, date: Date, today: Date = RoundCalendar.startOfDay()) -> String {
        template
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{when}", with: when(date, today: today))
    }

    /// Opens a WhatsApp chat with the number, with the text ready to send.
    static func whatsAppURL(digits: String, text: String) -> URL? {
        guard !digits.isEmpty else { return nil }
        var components = URLComponents(string: "https://wa.me/\(digits)")
        components?.queryItems = [URLQueryItem(name: "text", value: text)]
        return components?.url
    }
}
