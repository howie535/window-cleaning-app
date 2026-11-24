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
/// every tab and every Stats screen, logs a clean and a skip as swipes would, then sits idle, marking each phase in perf.txt. The clean is undone at
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
        // Every screen under Stats, with More figures open, then back.
        PerfProbe.mark("STATS")
        tabs.selection = .today
        tabs.tourMoreFigures = true
        try? await Task.sleep(for: .milliseconds(1500))
        for destination: StatsView.Destination in [.weeklyWork, .monthlyWork, .perHouse, .housesPerDay, .skipRate, .roundLength,
                                                    .taxYear, .priceRise, .ideal] {
            tabs.tourStats = destination
            try? await Task.sleep(for: .milliseconds(1500))
            tabs.tourStats = nil
            try? await Task.sleep(for: .milliseconds(800))
        }
        tabs.tourMoreFigures = false
        tabs.selection = .round
        try? await Task.sleep(for: .milliseconds(1500))
        PerfProbe.mark("LOG")
        let today = RoundCalendar.startOfDay()
        let customers = (try? context.fetch(FetchDescriptor<Customer>(sortBy: [SortDescriptor(\.sequence)]))) ?? []
        var undos: [() -> Void] = []
        let fresh = customers.filter { $0.status == .active && !$0.allVisits.contains { $0.date == today } }
        // A clean, then a skip, as swipes would.
        for (target, action) in zip(fresh.prefix(2), [VisitLogger.Action.cleanedPaid, .skipped]) {
            undos.append(VisitLogger.perform(action, for: target, in: context))
            try? context.save()
            try? await Task.sleep(for: .seconds(2))
        }
        try? await Task.sleep(for: .seconds(1))
        PerfProbe.mark("IDLE")
        try? await Task.sleep(for: .seconds(12))
        PerfProbe.mark("END")
        for undo in undos.reversed() { undo() }
        try? context.save()
    }
}

/// Development aid for the swipe check (Tools/swipe-check.sh): with `-RowProbe` in the Simulator, writes every Round
/// row appearing or disappearing, and every swipe, to Documents/rows.txt. A row that disappears and comes back straight
/// after a swipe is the blink. Does nothing otherwise.
enum RowProbe {
    #if targetEnvironment(simulator)
    static let enabled = CommandLine.arguments.contains("-RowProbe")
    #else
    static let enabled = false
    #endif

    static func log(_ event: String, _ name: String) {
        guard enabled else { return }
        let line = String(format: "%.3f %@ %@\n", Date().timeIntervalSince1970, event, name)
        let url = URL.documentsDirectory.appendingPathComponent("rows.txt")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
