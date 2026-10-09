import Foundation
import SwiftData

/// Development aid: launching the app in the Simulator with `-ImportFile <name>` imports that file
/// at startup and prints the acceptance report (aggregates only). `-ExportFile <name>` then writes
/// an export, for round-trip checks, and `-ReportFile <name>` writes the report text. Does nothing on a real device.
@MainActor
enum SimulatorImport {
    static func runIfRequested(container: ModelContainer) {
        #if targetEnvironment(simulator)
        let arguments = CommandLine.arguments
        guard let importIndex = arguments.firstIndex(of: "-ImportFile"), importIndex + 1 < arguments.count else { return }
        let context = container.mainContext

        // Names are relative to the app's Documents folder (the Simulator sandbox blocks other paths).
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return URL.documentsDirectory.appendingPathComponent(arguments[index + 1]).path
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: value(after: "-ImportFile") ?? ""))
            let summary = try ImportService.replaceAll(data: data, context: context, includeHistory: !arguments.contains("-CustomersOnly"))
            var report = "IMPORT OK: \(summary.customers) customers, \(summary.visits) visits, \(summary.skippedVisits) skipped for bad dates, backup written: \(summary.backupURL != nil)\n"
                + (try AcceptanceReport.make(in: context))
            if arguments.contains("-SelfTest") {
                report += "\n\n" + (try SimulatorSelfTest.run(in: context))
            }
            print(report)
            if let reportPath = value(after: "-ReportFile") {
                try report.write(toFile: reportPath, atomically: true, encoding: .utf8)
            }

            if arguments.contains("-Stage5") {
                let todayText = arguments.firstIndex(of: "-Today").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
                let pinned = todayText.flatMap(RoundCalendar.parseDay) ?? RoundCalendar.startOfDay()
                let text = try AcceptanceReport.stage5(in: context, today: pinned)
                if let path = value(after: "-Stage5File") { try text.write(toFile: path, atomically: true, encoding: .utf8) }
            }

            if let planPath = value(after: "-PlanFile") {
                // `-Today yyyy-MM-dd` pins the date so the plan can be compared against a known date.
                let todayText = arguments.firstIndex(of: "-Today").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
                let today = todayText.flatMap(RoundCalendar.parseDay) ?? RoundCalendar.startOfDay()
                try PlanDump.write(to: planPath, today: today, in: context)
                print("PLAN OK")
            }

            if let exportPath = value(after: "-ExportFile") {
                try ExportService.data(from: context).write(to: URL(fileURLWithPath: exportPath), options: .atomic)
                print("EXPORT OK")
            }
        } catch {
            print("IMPORT FAILED: \(error)")
            if let reportPath = value(after: "-ReportFile") {
                try? "IMPORT FAILED: \(error)".write(toFile: reportPath, atomically: true, encoding: .utf8)
            }
        }
        #endif
    }
}
