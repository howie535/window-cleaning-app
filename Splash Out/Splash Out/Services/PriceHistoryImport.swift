import Foundation
import SwiftData

/// Adds price history from the old yearly worksheets (Tools/price_history.py → price-history-app.json, built into the
/// app as PriceHistory2025.json) to the customers already in the app, once, on first open. A merge, never a replace:
/// it adds past rises and the first clean on the worksheets, and never changes a price, a visit or a payment.
/// Running it twice adds nothing the second time.
@MainActor
enum PriceHistoryImport {
    struct File: Decodable {
        var schema: Int
        var worksheets: [String]?
        var customers: [Record]
        /// Customers on the old worksheets who had stopped before the app: added as Cancelled.
        var former: [Former]?
    }

    struct Former: Decodable {
        var round: String
        var name: String
        var address: String
        var price: Double
        var everyOther: Bool
        var firstClean: String
        var lastClean: String
        var cleans: Int
        var worksheet: String
    }

    struct Record: Decodable {
        var id: String
        var round: String?
        var name: String?
        var address: String?
        var firstSeen: String?
        var changes: [Change]
    }

    struct Change: Decodable {
        var date: String
        var old: Double?
        var new: Double
        var source: String
    }

    /// What applying the file would do (or did).
    struct Plan {
        fileprivate var items: [(customer: Customer, record: Record)] = []
        var worksheets: [String] = []
        var matched = 0
        var notMatched: [String] = []
        var risesToAdd = 0
        var customersGettingRises = 0
        var customersGettingHistory = 0
        /// The worksheet's last rise doesn't match the app's price, so it isn't used as "last rise" (checked by hand).
        var priceDiffers: [String] = []
        /// Former customers not already in the app (same name), to add as Cancelled.
        var formerToAdd: [Former] = []
        var backupURL: URL?

        var summary: String {
            var parts = ["Adds \(risesToAdd) past \(risesToAdd == 1 ? "rise" : "rises") to \(customersGettingRises) customers"]
            parts.append("history back to the worksheets for \(customersGettingHistory)")
            var text = parts.joined(separator: ", ") + "."
            if !formerToAdd.isEmpty { text += " Adds \(formerToAdd.count) former customers as Cancelled." }
            if !notMatched.isEmpty { text += " \(notMatched.count) not matched." }
            if !priceDiffers.isEmpty { text += " \(priceDiffers.count) with a different price on the worksheet (left as they are)." }
            return text
        }
    }

    enum ImportError: LocalizedError {
        case unsupportedSchema(Int)
        var errorDescription: String? {
            switch self {
            case .unsupportedSchema(let v): "This price history file is schema \(v); this app reads schema 1."
            }
        }
    }

    static func decode(_ data: Data) throws -> File {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let file = try decoder.decode(File.self, from: data)
        guard file.schema == 1 else { throw ImportError.unsupportedSchema(file.schema) }
        return file
    }

    private static func clean(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }

    /// Match on the app's ID first (customers imported from the round workbook keep it), then name and address,
    /// then name within the same round when that's unique.
    static func plan(_ file: File, customers: [Customer], today: Date) -> Plan {
        var plan = Plan(worksheets: file.worksheets ?? [])
        let byID = Dictionary(customers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for record in file.customers {
            let customer: Customer? = {
                if let id = UUID(uuidString: record.id), let c = byID[id] { return c }
                guard let name = record.name else { return nil }
                let both = customers.filter { clean($0.name) == clean(name) && clean($0.address) == clean(record.address ?? "") }
                if both.count == 1 { return both[0] }
                let named = customers.filter { $0.round == (record.round ?? "") && clean($0.name) == clean(name) }
                return named.count == 1 ? named[0] : nil
            }()
            guard let customer else {
                plan.notMatched.append(record.name.map { "\(record.round ?? "") · \($0)" } ?? record.id)
                continue
            }
            plan.matched += 1
            plan.items.append((customer, record))
            let new = newChanges(record, for: customer, today: today)
            if !new.isEmpty { plan.risesToAdd += new.count; plan.customersGettingRises += 1 }
            if let first = record.firstSeen.flatMap(RoundCalendar.parseDay), customer.historyFrom.map({ first < $0 }) ?? true {
                plan.customersGettingHistory += 1
            }
            if let last = usable(record, today: today).last, Money.decimal(last.new) != customer.price {
                plan.priceDiffers.append("\(customer.name): worksheet \(Money.decimal(last.new).pounds), app \(customer.price.pounds)")
            }
        }
        let names = Set(customers.map { clean($0.name) })
        plan.formerToAdd = (file.former ?? []).filter { !names.contains(clean($0.name)) }
        return plan
    }

    /// Rises dated today or earlier, oldest first.
    private static func usable(_ record: Record, today: Date) -> [(date: Date, old: Double?, new: Double)] {
        record.changes.compactMap { c in
            guard let d = RoundCalendar.parseDay(c.date), d <= today, c.new > 0 else { return nil }
            return (d, c.old, c.new)
        }.sorted { $0.date < $1.date }
    }

    /// Rises not already logged: one with the same new price within 60 days counts as already there (the same rise
    /// logged with Done on the Price Rise page, a day or a clean apart).
    private static func newChanges(_ record: Record, for customer: Customer, today: Date) -> [(date: Date, old: Double?, new: Double)] {
        let existing = customer.priceChanges ?? []
        return usable(record, today: today).filter { c in
            !existing.contains { $0.newPrice == Money.decimal(c.new) && abs($0.date.timeIntervalSince(c.date)) <= 60 * 86_400 }
        }
    }

    static let mergedKey = "priceHistory2025Merged"

    /// The one-time merge of the 2025-6 worksheet history built into the app. Does nothing once done, or if the file
    /// isn't in this build. Returns what it did.
    @discardableResult
    static func mergeBundledOnce(context: ModelContext, today: Date = RoundCalendar.startOfDay()) -> Plan? {
        guard !UserDefaults.standard.bool(forKey: mergedKey),
              let url = Bundle.main.url(forResource: "PriceHistory2025", withExtension: "json"),
              let data = try? Data(contentsOf: url), let file = try? decode(data),
              let customers = try? context.fetch(FetchDescriptor<Customer>()), !customers.isEmpty
        else { return nil }
        guard let done = try? apply(plan(file, customers: customers, today: today), today: today, context: context) else { return nil }
        UserDefaults.standard.set(true, forKey: mergedKey)
        return done
    }

    /// Adds the history. A backup of what's there is written first.
    static func apply(_ plan: Plan, today: Date, context: ModelContext, backupDirectory: URL? = ExportService.backupDirectory) throws -> Plan {
        var done = plan
        if let backupDirectory {
            done.backupURL = try ExportService.writeBackup(from: context, to: backupDirectory)
        }
        for (customer, record) in plan.items {
            for c in newChanges(record, for: customer, today: today) {
                context.insert(PriceChange(date: c.date, oldPrice: c.old.map(Money.decimal) ?? 0, newPrice: Money.decimal(c.new),
                                           reason: .rise, customer: customer))
            }
            if let first = record.firstSeen.flatMap(RoundCalendar.parseDay), customer.historyFrom.map({ first < $0 }) ?? true {
                customer.historyFrom = first
            }
            // "Last rise" only moves to a worksheet rise that set the price they're on now, and only later.
            if let last = usable(record, today: today).last(where: { Money.decimal($0.new) == customer.price }),
               customer.priceSince.map({ last.date > $0 }) ?? true {
                customer.priceSince = last.date
            }
        }
        // Former customers: Cancelled, as they would have been when they stopped. No cleans are brought over, so no
        // totals change; when they were cleaned is kept in a note. Added at the end of the round order.
        var sequence = ((try? context.fetch(FetchDescriptor<Customer>()))?.map(\.sequence).max() ?? 0) + 1
        for f in plan.formerToAdd {
            guard let first = RoundCalendar.parseDay(f.firstClean), let last = RoundCalendar.parseDay(f.lastClean) else { continue }
            let cleans = f.cleans == 1 ? "1 clean" : "\(f.cleans) cleans"
            let customer = Customer(name: f.name, address: f.address, price: Money.decimal(f.price), sequence: sequence,
                                    round: f.round, status: .cancelled,
                                    notes: ["Stopped before the app: last cleaned \(RoundCalendar.shortWithYear(last)) (\(cleans) from \(RoundCalendar.shortWithYear(first)), \(f.worksheet) worksheet)."])
            customer.everyOther = f.everyOther
            customer.historyFrom = first
            context.insert(customer)
            sequence += 1
        }
        try context.save()
        return done
    }
}
