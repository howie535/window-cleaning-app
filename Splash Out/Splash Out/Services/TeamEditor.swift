import Foundation
import SwiftData

/// Adding, renaming and removing team members and crews, keeping the usual week, extra-day crew
/// and diary consistent with the names.
@MainActor
enum TeamEditor {
    struct Failure: LocalizedError {
        var errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private static func clean(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func contains(_ names: [String], _ name: String) -> Bool {
        names.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func addMember(_ raw: String, settings: AppSettings) throws {
        let name = clean(raw)
        guard !name.isEmpty else { throw Failure("Type a name first.") }
        guard !contains(settings.teamMembers, name) else { throw Failure("\(name) is already in the team.") }
        settings.teamMembers.append(name)
    }

    static func renameMember(from old: String, to raw: String, settings: AppSettings, crews: [Crew], workDays: [WorkDay]) throws {
        let new = clean(raw)
        guard !new.isEmpty else { throw Failure("Type a name first.") }
        if new == old { return }
        guard !contains(settings.teamMembers.filter { $0 != old }, new) else { throw Failure("\(new) is already in the team.") }

        func swap(_ names: [String]) -> [String] { names.map { $0 == old ? new : $0 } }
        settings.teamMembers = swap(settings.teamMembers)
        for crew in crews where crew.members.contains(old) {
            let oldName = crew.name
            let followedMembers = oldName == Crew.autoName(for: crew.members)
            crew.members = swap(crew.members)
            if followedMembers { crew.name = Crew.autoName(for: crew.members) }
            settings.usualWeek = settings.usualWeek.map { $0 == oldName ? crew.name : $0 }
            if settings.extraDayCrew == oldName { settings.extraDayCrew = crew.name }
        }
        for day in workDays where day.crewMembers.contains(old) { day.crewMembers = swap(day.crewMembers) }
    }

    static func removeMember(_ name: String, settings: AppSettings, crews: [Crew]) throws {
        if let crew = crews.first(where: { $0.members.contains(name) }) {
            throw Failure("\(name) is in the crew \"\(crew.name)\". Delete or change the crews they are in first.")
        }
        settings.teamMembers.removeAll { $0 == name }
    }

    @discardableResult
    static func addCrew(members: Set<String>, dayTarget: Decimal, settings: AppSettings, crews: [Crew], context: ModelContext) throws -> Crew {
        guard !members.isEmpty else { throw Failure("Choose at least one person.") }
        guard dayTarget >= 0 else { throw Failure("The day target can't be negative.") }
        let ordered = settings.teamMembers.filter { members.contains($0) }
        guard !crews.contains(where: { Set($0.members) == members }) else {
            throw Failure("There is already a crew with exactly these people.")
        }
        let crew = Crew(name: Crew.autoName(for: ordered), members: ordered, dayTarget: dayTarget)
        context.insert(crew)
        return crew
    }

    static func deleteCrew(_ crew: Crew, settings: AppSettings, context: ModelContext) {
        settings.usualWeek = settings.usualWeek.map { $0 == crew.name ? "" : $0 }
        if settings.extraDayCrew == crew.name { settings.extraDayCrew = "" }
        context.delete(crew)
    }
}
