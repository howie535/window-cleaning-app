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
            let summary = try ImportService.replaceAll(data: data, context: context)
            let report = "IMPORT OK: \(summary.customers) customers, \(summary.visits) visits, \(summary.skippedVisits) skipped for bad dates, backup written: \(summary.backupURL != nil)\n"
                + (try AcceptanceReport.make(in: context))
            print(report)
            if let reportPath = value(after: "-ReportFile") {
                try report.write(toFile: reportPath, atomically: true, encoding: .utf8)
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
