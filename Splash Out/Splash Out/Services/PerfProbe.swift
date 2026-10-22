import Foundation
import SwiftData

/// Development aid: with the `-PerfLog` launch argument in the Simulator, records how long each screen's own work
/// takes every time it rebuilds, in Documents/perf.txt. Does nothing otherwise.
enum PerfProbe {
    #if targetEnvironment(simulator)
    static let enabled = CommandLine.arguments.contains("-PerfLog")
    #else
    static let enabled = false
    #endif

    static func now() -> ContinuousClock.Instant? { enabled ? ContinuousClock.now : nil }

    static func end(_ name: String, _ start: ContinuousClock.Instant?) {
        guard let start else { return }
        let elapsed = ContinuousClock.now - start
        let ms = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        let line = String(format: "%.3f %@ %.1fms\n", Date().timeIntervalSince1970, name, ms)
        let url = URL.documentsDirectory.appendingPathComponent("perf.txt")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// A marker line in perf.txt, so the lag check can tell the phases of a tour apart.
    static func mark(_ name: String) {
        guard enabled else { return }
        end("MARK-\(name)", ContinuousClock.now)
    }
}

/// Development aid for the lag check (Tools/lag-check.sh): with `-PerfLog -LagTour` in the Simulator, the app visits
/// every tab, logs one clean as a swipe would, then sits idle, marking each phase in perf.txt. The clean is undone at
/// the end. Does nothing otherwise.
@MainActor
enum LagTour {
    #if targetEnvironment(simulator)
    static let enabled = CommandLine.arguments.contains("-LagTour")
    #else
    static let enabled = false
    #endif

    static func run(tabs: TabState, context: ModelContext) async {
        guard enabled else { return }
        try? await Task.sleep(for: .seconds(3))
        PerfProbe.mark("TOUR")
        for tab in [AppTab.round, .customers, .owed, .more, .today, .round] {
            tabs.selection = tab
            try? await Task.sleep(for: .milliseconds(1500))
        }
        PerfProbe.mark("LOG")
        let today = RoundCalendar.startOfDay()
        let customers = (try? context.fetch(FetchDescriptor<Customer>(sortBy: [SortDescriptor(\.sequence)]))) ?? []
        var undo: (() -> Void)?
        if let target = customers.first(where: { $0.status == .active && !$0.allVisits.contains { $0.date == today } }) {
            undo = VisitLogger.perform(.cleanedPaid, for: target, in: context)
            try? context.save()
        }
        try? await Task.sleep(for: .seconds(3))
        PerfProbe.mark("IDLE")
        try? await Task.sleep(for: .seconds(12))
        PerfProbe.mark("END")
        undo?()
        try? context.save()
    }
}
