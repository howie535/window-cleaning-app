import Foundation
import EventKit
import SwiftData
import UIKit

/// Puts the working diary on a "Splash Out" calendar in the phone's Calendar app, so it can be shared with the crew.
/// One-way: the app writes the calendar, nothing is read back. Only the crew (or "Day off") goes on it: no targets,
/// notes, customers or addresses. Each event is an all-day event on the day.
enum CalendarPlan {
    /// What the calendar should say, for each working or day-off date from `start` for `days` days.
    @MainActor
    static func entries(settings: AppSettings, crews: [Crew], workDays: [WorkDay], from start: Date, days: Int = 120) -> [Date: String] {
        let resolver = RoundPlanner.DayResolver(settings: settings, crews: crews, workDays: workDays, customers: [])
        let diary = Dictionary(workDays.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [Date: String] = [:]
        for offset in 0..<days {
            guard let date = RoundCalendar.london.date(byAdding: .day, value: offset, to: start) else { continue }
            if diary[date]?.dayOff == true {
                result[date] = "Day off"
            } else if resolver.target(on: date) > 0 {
                let name = resolver.crewName(on: date)
                if !name.isEmpty { result[date] = name }
            }
        }
        return result
    }
}

@MainActor
enum CalendarSync {
    static let calendarTitle = "Splash Out"
    static let enabledKey = "calendar.enabled"
    private static let calendarIDKey = "calendar.identifier"
    private static let marker = "splash-out:"

    enum Outcome: Equatable {
        case updated(added: Int, changed: Int, removed: Int)
        case removed(Int)
        case notAllowed
        case failed(String)

        var message: String {
            switch self {
            case .updated(let added, let changed, let removed):
                if added + changed + removed == 0 { return "The calendar was already up to date." }
                return "Calendar updated: \(added) added, \(changed) changed, \(removed) removed."
            case .removed(let count):
                return count == 0 ? "There was no Splash Out calendar to remove." : "The Splash Out calendar was removed. Anyone you shared it with no longer sees it."
            case .notAllowed:
                return "Splash Out isn't allowed to use Calendar. You can allow it in Settings > Privacy & Security > Calendars."
            case .failed(let reason):
                return "Couldn't update the calendar: \(reason)"
            }
        }
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Updates the calendar if the user has switched it on. Quiet: used after changes and when the app opens.
    static func syncIfEnabled(context: ModelContext) async {
        guard isEnabled else { return }
        _ = await sync(context: context)
    }

    static func sync(context: ModelContext) async -> Outcome {
        let store = EKEventStore()
        do {
            guard try await store.requestFullAccessToEvents() else { return .notAllowed }

            let settings = try context.fetch(FetchDescriptor<AppSettings>()).first ?? AppSettings()
            let crews = try context.fetch(FetchDescriptor<Crew>())
            let workDays = try context.fetch(FetchDescriptor<WorkDay>())
            let today = RoundCalendar.startOfDay()
            let wanted = CalendarPlan.entries(settings: settings, crews: crews, workDays: workDays, from: today)

            let calendar = try findOrCreateCalendar(in: store)
            let end = RoundCalendar.london.date(byAdding: .day, value: 130, to: today)!
            let existing = store.events(matching: store.predicateForEvents(withStart: today, end: end, calendars: [calendar]))

            var added = 0, changed = 0, removed = 0
            var seen = Set<Date>()
            for event in existing {
                let date = RoundCalendar.startOfDay(event.startDate)
                if let title = wanted[date], !seen.contains(date) {
                    seen.insert(date)
                    if event.title != title || !event.isAllDay {
                        event.title = title
                        event.isAllDay = true
                        try store.save(event, span: .thisEvent)
                        changed += 1
                    }
                } else {
                    try store.remove(event, span: .thisEvent)
                    removed += 1
                }
            }
            for (date, title) in wanted where !seen.contains(date) {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                event.title = title
                event.isAllDay = true
                event.startDate = date
                event.endDate = date
                event.notes = marker + RoundCalendar.dayString(date)
                try store.save(event, span: .thisEvent)
                added += 1
            }
            try store.commit()
            return .updated(added: added, changed: changed, removed: removed)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Removes the calendar (and so the events on it) from this phone.
    static func removeCalendar() async -> Outcome {
        let store = EKEventStore()
        do {
            guard try await store.requestFullAccessToEvents() else { return .notAllowed }
            var doomed: [EKCalendar] = []
            if let id = UserDefaults.standard.string(forKey: calendarIDKey), let calendar = store.calendar(withIdentifier: id) {
                doomed.append(calendar)
            }
            for calendar in store.calendars(for: .event) where calendar.title == calendarTitle && calendar.allowsContentModifications
                && !doomed.contains(where: { $0.calendarIdentifier == calendar.calendarIdentifier }) {
                doomed.append(calendar)
            }
            for calendar in doomed { try store.removeCalendar(calendar, commit: true) }
            UserDefaults.standard.removeObject(forKey: calendarIDKey)
            return .removed(doomed.count)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func findOrCreateCalendar(in store: EKEventStore) throws -> EKCalendar {
        if let id = UserDefaults.standard.string(forKey: calendarIDKey), let calendar = store.calendar(withIdentifier: id) {
            return calendar
        }
        if let existing = store.calendars(for: .event).first(where: { $0.title == calendarTitle && $0.allowsContentModifications }) {
            UserDefaults.standard.set(existing.calendarIdentifier, forKey: calendarIDKey)
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarTitle
        calendar.cgColor = UIColor.systemBlue.cgColor
        // iCloud is the one that can be shared with other people; fall back to this phone only if there is none.
        let source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }
            ?? store.sources.first { $0.sourceType == .local }
        guard let source else { throw CalendarError.noPlace }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        UserDefaults.standard.set(calendar.calendarIdentifier, forKey: calendarIDKey)
        return calendar
    }

    private enum CalendarError: LocalizedError {
        case noPlace
        var errorDescription: String? { "There's no calendar account on this device to put it in." }
    }
}
