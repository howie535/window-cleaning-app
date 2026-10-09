import Foundation
import SwiftData

#if targetEnvironment(simulator)
/// Development aid: writes the Next Up plan as plain lines so it can be compared against a reference.
/// DAY lines list the working days; each customer line is `id,date` (or `later`).
@MainActor
enum PlanDump {
    static func write(to path: String, today: Date, in context: ModelContext) throws {
        let customers = try context.fetch(FetchDescriptor<Customer>(sortBy: [SortDescriptor(\.sequence)]))
        let crews = try context.fetch(FetchDescriptor<Crew>())
        let workDays = try context.fetch(FetchDescriptor<WorkDay>())
        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first
        let plan = RoundPlanner.plan(customers: customers, settings: settings, crews: crews, workDays: workDays, today: today)

        var lines = ["TODAY,\(RoundCalendar.dayString(today))"]
        for day in plan.days {
            lines.append("DAY,\(RoundCalendar.dayString(day.date)),\(day.target),\(day.bookTo),\(day.crewName)")
            for customer in day.customers { lines.append("\(customer.id.uuidString.lowercased()),\(RoundCalendar.dayString(day.date))") }
        }
        for customer in plan.later { lines.append("\(customer.id.uuidString.lowercased()),later") }
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}
#endif
