import Foundation
import Observation
import UIKit

/// Today's date for the screens that depend on it (Stats, Round, Weekly, Owed).
/// It moves on at midnight and whenever the app is opened, so "this week" and "today" never get stuck on yesterday.
@MainActor
@Observable
final class RoundClock {
    private(set) var today: Date = RoundCalendar.startOfDay()
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Call when the app comes to the front.
    func refresh() {
        let now = RoundCalendar.startOfDay()
        if now != today { today = now }
    }
}
