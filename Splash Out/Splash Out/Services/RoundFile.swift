import Foundation

/// The import/export file (Docs/SPEC.md section 6). Used for both directions so they round-trip.
/// Keys are snake_case in the file; money is a plain number, converted to Decimal on the way in.
struct RoundFile: Codable {
    var schema: Int
    var generatedAt: String
    var source: String?
    var settings: SettingsRecord
    var customers: [CustomerRecord]
    var diary: [DiaryRecord]
    var tips: [TipRecord]

    static let currentSchema = 1

    struct SettingsRecord: Codable {
        var crews: [CrewRecord]
        var usualWeek: [String: String?]
        var extraDayCrew: String
        var minHousesForWorkingDay: Int
        var overbook: Double
        var nextUpHideWeeks: Int
        var nextUpHideWeeksEveryOther: Int
        var priceRise: PriceRiseRecord
        var recordsStart: String
    }

    struct CrewRecord: Codable {
        var name: String
        var members: [String]
        var dayTarget: Double
    }

    struct PriceRiseRecord: Codable {
        var date: String?
        var percent: Double
        var rounding: String
        var delayMonths: Int
        var dueAfterMonths: Int
    }

    struct CustomerRecord: Codable {
        var id: String
        var sequence: Int
        var round: String
        var area: String?
        var status: String
        var name: String
        var address: String
        var phone: String?
        var price: Double
        var priceSince: String?
        var everyOther: Bool
        var frontOnly: Bool
        var contact: String
        var payMethod: String?
        var notes: [String]
        var visits: [VisitRecord]
    }

    struct VisitRecord: Codable {
        var date: String?
        var kind: String
        var listPrice: Double
        var charged: Double
        var paid: Double
        var paidDate: String?
        var note: String?
        var dateEstimated: Bool?
        var creditApplied: Double?
    }

    struct DiaryRecord: Codable {
        var date: String
        var dayOff: Bool
        var crew: [String]?
        var note: String?
    }

    struct TipRecord: Codable {
        var date: String
        var name: String
        var amount: Double
    }

    static func decode(_ data: Data) throws -> RoundFile {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RoundFile.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

enum Money {
    /// Two-decimal Decimal from a JSON number, without binary-float artefacts (0.1 stays 0.1).
    static func decimal(_ value: Double) -> Decimal {
        Decimal(string: String(format: "%.2f", value)) ?? Decimal(value)
    }

    static func double(_ value: Decimal) -> Double {
        (NSDecimalNumber(decimal: value).doubleValue * 100).rounded() / 100
    }
}
