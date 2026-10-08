import Foundation
import SwiftData

@Model
final class PriceChange {
    var date: Date = Date()
    var oldPrice: Decimal = 0
    var newPrice: Decimal = 0
    var reasonRaw: String = PriceChangeReason.rise.rawValue
    var customer: Customer?

    init(date: Date, oldPrice: Decimal, newPrice: Decimal, reason: PriceChangeReason, customer: Customer? = nil) {
        self.date = date
        self.oldPrice = oldPrice
        self.newPrice = newPrice
        self.reasonRaw = reason.rawValue
        self.customer = customer
    }

    var reason: PriceChangeReason {
        get { PriceChangeReason(rawValue: reasonRaw) ?? .rise }
        set { reasonRaw = newValue.rawValue }
    }
}

@Model
final class Crew {
    var name: String = ""
    var members: [String] = []
    var dayTarget: Decimal = 0

    init(name: String, members: [String], dayTarget: Decimal) {
        self.name = name
        self.members = members
        self.dayTarget = dayTarget
    }

    /// The valid crews from the spec.
    static let defaults: [(name: String, members: [String], target: Decimal)] = [
        ("Howie + Dad", ["Howie", "Dad"], 400),
        ("Howie + Rebekah", ["Howie", "Rebekah"], 300),
        ("Dad + Rebekah", ["Dad", "Rebekah"], 300),
        ("Howie alone", ["Howie"], 300),
        ("Dad alone", ["Dad"], 250),
    ]
}

/// Only days that differ from the usual week are stored.
@Model
final class WorkDay {
    var date: Date = Date()
    var dayOff: Bool = false
    /// Crew override for the day (member names). Empty means no override.
    var crewMembers: [String] = []
    var note: String?

    init(date: Date, dayOff: Bool, crewMembers: [String], note: String?) {
        self.date = date
        self.dayOff = dayOff
        self.crewMembers = crewMembers
        self.note = note
    }
}

/// Tips are never counted as income anywhere.
@Model
final class Tip {
    var date: Date = Date()
    var name: String = ""
    var amount: Decimal = 0

    init(date: Date, name: String, amount: Decimal) {
        self.date = date
        self.name = name
        self.amount = amount
    }
}

/// One row only.
@Model
final class AppSettings {
    /// Crew name for Monday...Sunday. Empty string means no one works that day.
    var usualWeek: [String] = ["Howie + Dad", "Howie + Dad", "Howie + Rebekah", "", "", "", ""]
    var extraDayCrew: String = "Howie + Dad"
    var minHousesForWorkingDay: Int = 5
    var overbook: Double = 0.10
    var nextUpHideWeeks: Int = 3
    var nextUpHideWeeksEveryOther: Int = 8
    var priceRiseDate: Date?
    var priceRisePercent: Double = 0.10
    var priceRiseDelayMonths: Int = 12
    var priceRiseDueAfterMonths: Int = 24
    var recordsStart: Date = RoundCalendar.date(year: 2026, month: 4, day: 6)

    init() {}
}
