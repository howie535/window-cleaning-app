import Foundation
import SwiftData

@MainActor
enum ImportService {
    struct Summary {
        var customers = 0
        var visits = 0
        var diary = 0
        var tips = 0
        /// Visits left out because their date wasn't a real one.
        var skippedVisits = 0
        var statusCounts: [String: Int] = [:]
        var backupURL: URL?
    }

    enum ImportError: LocalizedError {
        case unsupportedSchema(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedSchema(let version):
                "This file is schema \(version), but this version of the app reads schema \(RoundFile.currentSchema)."
            }
        }
    }

    /// Dates before this can't be real (the workbook had a few 1900-era mistakes).
    private static let earliestRealDate = RoundCalendar.date(year: 2000, month: 1, day: 1)

    /// Replace, don't merge: wipes customers, visits, diary, tips and settings, then loads the file.
    /// A backup of what's there is written first (when there is anything to back up).
    static func replaceAll(data: Data, context: ModelContext, backupDirectory: URL? = ExportService.backupDirectory) throws -> Summary {
        let file = try RoundFile.decode(data)
        guard file.schema == RoundFile.currentSchema else { throw ImportError.unsupportedSchema(file.schema) }

        var summary = Summary()

        if let backupDirectory, try context.fetchCount(FetchDescriptor<Customer>()) > 0 {
            summary.backupURL = try ExportService.writeBackup(from: context, to: backupDirectory)
        }

        try context.delete(model: Visit.self)
        try context.delete(model: PriceChange.self)
        try context.delete(model: Customer.self)
        try context.delete(model: WorkDay.self)
        try context.delete(model: Tip.self)
        try context.delete(model: Crew.self)
        try context.delete(model: AppSettings.self)

        insertSettings(file.settings, into: context)

        for record in file.customers {
            let customer = Customer(
                name: record.name,
                address: record.address,
                phone: record.phone.map(UKPhoneNumber.toNationalFormat) ?? "",
                price: Money.decimal(record.price),
                sequence: record.sequence,
                round: record.round,
                area: record.area ?? "",
                status: CustomerStatus(rawValue: record.status) ?? .active,
                notes: record.notes
            )
            customer.id = UUID(uuidString: record.id) ?? UUID()
            customer.priceSince = record.priceSince.flatMap(RoundCalendar.parseDay)
            customer.everyOther = record.everyOther
            customer.frontOnly = record.frontOnly
            customer.contact = ContactMethod(rawValue: record.contact) ?? .whatsapp
            customer.payMethod = PayMethod.fromImport(record.payMethod)
            context.insert(customer)
            summary.customers += 1
            summary.statusCounts[customer.statusRaw, default: 0] += 1

            for visitRecord in record.visits {
                guard let dateString = visitRecord.date,
                      let date = RoundCalendar.parseDay(dateString),
                      date >= earliestRealDate
                else {
                    summary.skippedVisits += 1
                    continue
                }
                let visit = Visit(
                    date: date,
                    kind: VisitKind(rawValue: visitRecord.kind) ?? .cleaned,
                    listPrice: Money.decimal(visitRecord.listPrice),
                    charged: Money.decimal(visitRecord.charged),
                    paid: Money.decimal(visitRecord.paid),
                    paidDate: visitRecord.paidDate.flatMap(RoundCalendar.parseDay),
                    note: visitRecord.note,
                    dateEstimated: visitRecord.dateEstimated ?? false
                )
                context.insert(visit)
                visit.customer = customer
                summary.visits += 1
            }
        }

        for entry in file.diary {
            guard let date = RoundCalendar.parseDay(entry.date) else { continue }
            context.insert(WorkDay(date: date, dayOff: entry.dayOff, crewMembers: entry.crew ?? [], note: entry.note))
            summary.diary += 1
        }

        for tip in file.tips {
            guard let date = RoundCalendar.parseDay(tip.date) else { continue }
            context.insert(Tip(date: date, name: tip.name, amount: Money.decimal(tip.amount)))
            summary.tips += 1
        }

        try context.save()
        return summary
    }

    private static func insertSettings(_ record: RoundFile.SettingsRecord, into context: ModelContext) {
        let settings = AppSettings()
        let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        settings.usualWeek = days.map { (record.usualWeek[$0] ?? nil) ?? "" }
        settings.extraDayCrew = record.extraDayCrew
        settings.minHousesForWorkingDay = record.minHousesForWorkingDay
        settings.overbook = record.overbook
        settings.nextUpHideWeeks = record.nextUpHideWeeks
        settings.nextUpHideWeeksEveryOther = record.nextUpHideWeeksEveryOther
        settings.priceRiseDate = record.priceRise.date.flatMap(RoundCalendar.parseDay)
        settings.priceRisePercent = record.priceRise.percent
        settings.priceRiseDelayMonths = record.priceRise.delayMonths
        settings.priceRiseDueAfterMonths = record.priceRise.dueAfterMonths
        if let start = RoundCalendar.parseDay(record.recordsStart) {
            settings.recordsStart = start
        }
        context.insert(settings)

        if record.crews.isEmpty {
            for crew in Crew.defaults {
                context.insert(Crew(name: crew.name, members: crew.members, dayTarget: crew.target))
            }
        } else {
            for crew in record.crews {
                context.insert(Crew(name: crew.name, members: crew.members, dayTarget: Money.decimal(crew.dayTarget)))
            }
        }
    }
}
