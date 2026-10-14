import Foundation
import UIKit

/// The WhatsApp message for a day's customers, and the link that opens it.
enum DayMessage {
    static let defaultTemplate = "Hi {name}, we're planning to clean your windows on {date}. Let us know if that doesn't suit!"
    static let templateKey = "whatsapp.dayTemplate"

    /// Where the ticks for who has been messaged for a day are kept.
    static func sentKey(_ date: Date) -> String { "messaged.\(RoundCalendar.dayString(date))" }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = RoundCalendar.london.timeZone
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = RoundCalendar.london.timeZone
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    /// "Tuesday 13 October".
    static func fullDate(_ date: Date) -> String { fullDateFormatter.string(from: date) }

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
            .replacingOccurrences(of: "{date}", with: fullDate(date))
    }

    /// Opens a WhatsApp chat with the number, with the text ready to send.
    static func whatsAppURL(digits: String, text: String) -> URL? {
        guard !digits.isEmpty else { return nil }
        var components = URLComponents(string: "https://wa.me/\(digits)")
        components?.queryItems = [URLQueryItem(name: "text", value: text)]
        return components?.url
    }
}

/// A WhatsApp reminder for a customer who owes, offered when skipping them (wording in Settings).
enum OwedReminder {
    static let templateKey = "whatsapp.owedReminder"
    static let defaultTemplate = "Hi {name}, we called today but weren't able to clean. Just a reminder that {amount} is still owing from your last {cleans}. Thank you!"

    @MainActor
    static func text(template: String, for customer: Customer) -> String {
        let owed = RoundMetrics.moneyOwed([customer])
        return template
            .replacingOccurrences(of: "{name}", with: customer.name)
            .replacingOccurrences(of: "{amount}", with: owed.amount.pounds)
            .replacingOccurrences(of: "{cleans}", with: owed.cleans == 1 ? "clean" : "\(owed.cleans) cleans")
    }

    static func canSend(to customer: Customer) -> Bool { customer.contact == .whatsapp && !customer.whatsAppDigits.isEmpty }

    /// Opens WhatsApp with the reminder ready to send.
    @MainActor
    static func open(for customer: Customer) {
        let template = UserDefaults.standard.string(forKey: templateKey) ?? defaultTemplate
        guard let url = DayMessage.whatsAppURL(digits: customer.whatsAppDigits, text: text(template: template, for: customer)) else { return }
        UIApplication.shared.open(url)
    }
}
