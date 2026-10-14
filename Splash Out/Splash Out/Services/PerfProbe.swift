import Foundation

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
}
