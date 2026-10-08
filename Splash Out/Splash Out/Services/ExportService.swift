import Foundation
import SwiftData

@MainActor
enum ExportService {
    private static let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

    static func makeFile(from context: ModelContext) throws -> RoundFile {
        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first ?? AppSettings()
        let crews = try context.fetch(FetchDescriptor<Crew>(sortBy: [SortDescriptor(\.name)]))
        let customers = try context.fetch(FetchDescriptor<Customer>(sortBy: [SortDescriptor(\.sequence)]))
        let diary = try context.fetch(FetchDescriptor<WorkDay>(sortBy: [SortDescriptor(\.date)]))
        let tips = try context.fetch(FetchDescriptor<Tip>(sortBy: [SortDescriptor(\.date)]))

        var usualWeek: [String: String?] = [:]
        for (index, day) in weekdays.enumerated() {
            let name = index < settings.usualWeek.count ? settings.usualWeek[index] : ""
            usualWeek.updateValue(name.isEmpty ? nil : name, forKey: day)
        }

        let settingsRecord = RoundFile.SettingsRecord(
            crews: crews.map { .init(name: $0.name, members: $0.members, dayTarget: Money.double($0.dayTarget)) },
            usualWeek: usualWeek,
            extraDayCrew: settings.extraDayCrew,
            minHousesForWorkingDay: settings.minHousesForWorkingDay,
            overbook: settings.overbook,
            nextUpHideWeeks: settings.nextUpHideWeeks,
            nextUpHideWeeksEveryOther: settings.nextUpHideWeeksEveryOther,
            priceRise: .init(
                date: settings.priceRiseDate.map(RoundCalendar.dayString),
                percent: settings.priceRisePercent,
                rounding: "nearest_pound_half_down",
                delayMonths: settings.priceRiseDelayMonths,
                dueAfterMonths: settings.priceRiseDueAfterMonths
            ),
            recordsStart: RoundCalendar.dayString(settings.recordsStart)
        )

        let customerRecords: [RoundFile.CustomerRecord] = customers.map { customer in
            let visits = customer.allVisits.sorted { $0.date < $1.date }.map { visit in
                RoundFile.VisitRecord(
                    date: RoundCalendar.dayString(visit.date),
                    kind: visit.kindRaw,
                    listPrice: Money.double(visit.listPrice),
                    charged: Money.double(visit.charged),
                    paid: Money.double(visit.paid),
                    paidDate: visit.paidDate.map(RoundCalendar.dayString),
                    note: visit.note,
                    dateEstimated: visit.dateEstimated ? true : nil,
                    creditApplied: visit.creditApplied == 0 ? nil : Money.double(visit.creditApplied)
                )
            }
            return RoundFile.CustomerRecord(
                id: customer.id.uuidString.lowercased(),
                sequence: customer.sequence,
                round: customer.round,
                area: customer.area.isEmpty ? nil : customer.area,
                status: customer.statusRaw,
                name: customer.name,
                address: customer.address,
                phone: customer.phone.isEmpty ? nil : customer.phone,
                price: Money.double(customer.price),
                priceSince: customer.priceSince.map(RoundCalendar.dayString),
                everyOther: customer.everyOther,
                frontOnly: customer.frontOnly,
                contact: customer.contactRaw,
                payMethod: customer.payMethodRaw,
                notes: customer.notes,
                visits: visits
            )
        }

        return RoundFile(
            schema: RoundFile.currentSchema,
            generatedAt: RoundCalendar.timestampString(),
            source: "Splash Out app",
            settings: settingsRecord,
            customers: customerRecords,
            diary: diary.map {
                .init(date: RoundCalendar.dayString($0.date), dayOff: $0.dayOff,
                      crew: $0.crewMembers.isEmpty ? nil : $0.crewMembers, note: $0.note)
            },
            tips: tips.map {
                .init(date: RoundCalendar.dayString($0.date), name: $0.name, amount: Money.double($0.amount))
            }
        )
    }

    static func data(from context: ModelContext) throws -> Data {
        try makeFile(from: context).encoded()
    }

    /// Writes a timestamped backup into `directory` and returns its URL.
    @discardableResult
    static func writeBackup(from context: ModelContext, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("splash-out-backup-\(RoundCalendar.fileStamp()).json")
        try data(from: context).write(to: url, options: .atomic)
        return url
    }

    nonisolated static var backupDirectory: URL {
        URL.documentsDirectory.appendingPathComponent("Backups", isDirectory: true)
    }
}
