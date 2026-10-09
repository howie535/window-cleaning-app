import Foundation
import SwiftData
import CoreLocation

/// Brings customers in from a CSV: picks the columns from their headings, skips anyone already in the app
/// (same name and address) and adds the rest at the end of the round.
enum CustomerCSVImport {
    struct Result {
        var imported: Int
        var skipped: Int
        var duplicates: Int
    }

    private static func duplicateKey(name: String, address: String) -> String {
        func clean(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
        return clean(name) + "|" + clean(address)
    }

    static func autoDetectedMapping(for headers: [String]) -> [Int: ImportField] {
        var mapping: [Int: ImportField] = [:]
        for (index, header) in headers.enumerated() {
            let lower = header.lowercased()
            if lower.contains("price since") || lower.contains("price_since") {
                continue
            } else if lower.contains("first") && lower.contains("name") {
                mapping[index] = .firstName
            } else if (lower.contains("last") || lower.contains("surname") || lower.contains("family")) && (lower.contains("name") || lower.contains("surname")) {
                mapping[index] = .lastName
            } else if lower.contains("surname") {
                mapping[index] = .lastName
            } else if lower.contains("name") {
                mapping[index] = .name
            } else if lower.contains("address") {
                mapping[index] = .address
            } else if lower.contains("price") || lower.contains("cost") {
                mapping[index] = .price
            } else if lower.contains("phone") {
                mapping[index] = .phone
            } else if lower.contains("note") {
                mapping[index] = .accessNotes
            } else if lower.contains("round") {
                mapping[index] = .round
            } else if lower.contains("area") {
                mapping[index] = .area
            } else if lower.contains("status") {
                mapping[index] = .status
            } else if lower.contains("every") {
                mapping[index] = .everyOther
            } else if lower.contains("front") {
                mapping[index] = .frontOnly
            } else if lower.contains("contact") {
                mapping[index] = .contact
            } else if lower.contains("pay") {
                mapping[index] = .payMethod
            }
        }
        return mapping
    }

    private static var maxSequenceDescriptor: FetchDescriptor<Customer> {
        var descriptor = FetchDescriptor<Customer>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    @MainActor
    static func run(mapping: [Int: ImportField], rows: [[String]], context modelContext: ModelContext) -> Result {
        var imported = 0
        var skipped = 0
        var duplicates = 0
        var existing = Set(((try? modelContext.fetch(FetchDescriptor<Customer>())) ?? []).map { duplicateKey(name: $0.name, address: $0.address) })
        var nextSequence = ((try? modelContext.fetch(maxSequenceDescriptor))?.first?.sequence ?? 0) + 1

        for row in rows {
            var name = ""
            var firstName = "", lastName = ""
            var address = ""
            var phone = ""
            var notes = ""
            var price: Decimal = 0
            var round = "", area = ""
            var status: CustomerStatus?
            var everyOther = false, frontOnly = false
            var contact: ContactMethod?
            var payMethod: PayMethod?

            func isYes(_ value: String) -> Bool { ["yes", "y", "true", "1"].contains(value.lowercased()) }

            for (index, field) in mapping {
                guard index < row.count else { continue }
                let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                switch field {
                case .name: name = value
                case .firstName: firstName = value
                case .lastName: lastName = value
                case .address: address = value
                case .price: price = CSVParser.parsePrice(value) ?? 0
                case .phone: phone = UKPhoneNumber.toNationalFormat(value)
                case .accessNotes: notes = value
                case .round: round = value
                case .area: area = value
                case .status:
                    let key = value.lowercased().replacingOccurrences(of: " ", with: "_")
                    status = CustomerStatus(rawValue: key)
                case .everyOther: everyOther = isYes(value)
                case .frontOnly: frontOnly = isYes(value)
                case .contact: contact = ContactMethod(rawValue: value.lowercased())
                case .payMethod: payMethod = PayMethod.fromImport(value)
                case .ignore: break
                }
            }

            if name.isEmpty { name = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }

            guard !name.isEmpty else {
                skipped += 1
                continue
            }

            // Already in the app (same name and address): don't add them twice.
            let key = duplicateKey(name: name, address: address)
            if existing.contains(key) {
                duplicates += 1
                continue
            }
            existing.insert(key)

            let customer = Customer(
                name: name,
                address: address,
                phone: phone,
                price: price,
                sequence: nextSequence,
                notes: notes.isEmpty ? [] : notes.components(separatedBy: " | ")
            )
            customer.round = round
            customer.area = area
            if let status { customer.status = status }
            customer.everyOther = everyOther
            customer.frontOnly = frontOnly
            if let contact { customer.contact = contact }
            customer.payMethod = payMethod
            modelContext.insert(customer)
            imported += 1
            nextSequence += 1

            let addressToFind = address
            if !addressToFind.isEmpty {
                Task {
                    let coordinate = await Geocoding.coordinate(for: addressToFind)
                    customer.latitude = coordinate?.latitude
                    customer.longitude = coordinate?.longitude
                }
            }
        }

        return Result(imported: imported, skipped: skipped, duplicates: duplicates)
    }
}
