import Foundation

/// Clusters of neighbours that shouldn't be split across two days (Docs: day-two notes).
/// A cluster is a run of customers next to each other in round order on the same street, unless a customer is set
/// to always or never join the one before them. Pure logic on plain values, so it can be tested alone.
enum RoundGrouping {
    /// The street part of an address: first line, lower case, punctuation gone, house numbers ("33a") dropped.
    static func streetKey(_ address: String) -> String {
        let firstLine = address.split(separator: ",").first.map(String.init) ?? address
        let cleaned = String(firstLine.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " })
        var words = cleaned.split(separator: " ").map(String.init)
        words.removeAll { $0.contains(where: \.isNumber) }
        return words.joined(separator: " ")
    }

    /// Same street: the keys match, or one is the other with a house name in front
    /// ("blue haze lon pendyffryn" and "lon pendyffryn"). A one-word street must match exactly.
    static func sameStreet(_ a: String, _ b: String) -> Bool {
        let ka = streetKey(a), kb = streetKey(b)
        guard !ka.isEmpty, !kb.isEmpty else { return false }
        if ka == kb { return true }
        let (long, short) = ka.count >= kb.count ? (ka, kb) : (kb, ka)
        return short.split(separator: " ").count >= 2 && long.hasSuffix(" " + short)
    }

    /// A group number for each customer, given in round order. `joinsPrevious` is the customer's own setting:
    /// nil means automatic (same street as the one before), true always joins, false always starts a new group.
    static func groups(_ ordered: [(address: String, joinsPrevious: Bool?)]) -> [Int] {
        var result: [Int] = []
        var group = 0
        for (index, item) in ordered.enumerated() {
            if index > 0 {
                let joins = item.joinsPrevious ?? sameStreet(ordered[index - 1].address, item.address)
                if !joins { group += 1 }
            }
            result.append(group)
        }
        return result
    }
}
