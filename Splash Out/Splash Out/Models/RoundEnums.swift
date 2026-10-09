import Foundation

// Stored on the models as raw strings (CloudKit-friendly); these give typed access.
// Raw values match the import file (Docs/SPEC.md section 6).

enum CustomerStatus: String, CaseIterable, Identifiable {
    case active
    case notStarted = "not_started"
    case paused
    case leaving
    case cancelled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .active: "Active"
        case .notStarted: "Not started"
        case .paused: "Paused"
        case .leaving: "Leaving"
        case .cancelled: "Cancelled"
        }
    }
}

enum VisitKind: String {
    case cleaned
    case skipped
    case notDue = "not_due"
}

enum ContactMethod: String, CaseIterable, Identifiable {
    case whatsapp
    case ring

    var id: String { rawValue }
}

enum PayMethod: String, CaseIterable, Identifiable {
    case cash
    case bacs
    case standingOrder = "standing_order"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cash: "Cash"
        case .bacs: "BACS"
        case .standingOrder: "Standing order"
        }
    }

    /// Imported files may write standing order as "so".
    static func fromImport(_ raw: String?) -> PayMethod? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return nil }
        if raw == "so" { return .standingOrder }
        return PayMethod(rawValue: raw)
    }
}

enum PriceChangeReason: String {
    case rise
    case correction
    case newQuote = "new_quote"
}
