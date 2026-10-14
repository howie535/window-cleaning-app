import Foundation

/// Clusters of neighbours that shouldn't be split across two days (Docs: day-two notes).
/// A cluster is a run of customers next to each other in round order on the same street, unless a customer is set
/// to always or never join the one before them. Pure logic on plain values, so it can be tested alone.
enum RoundGrouping {
    /// The street part of an address: first line, lower case, punctuation gone, house numbers ("33a") dropped.
    static func streetKey(_ address: String) -> String {
        // The part of the address that names the street: the first with a house number or a street word
        // ("Coddington, High St" is High St), otherwise the first part.
        let parts = address.split(separator: ",").map { String($0).lowercased() }
        let streetPart = parts.first { part in
            part.contains(where: \.isNumber) || part.split(whereSeparator: { !$0.isLetter }).contains { streetWords.contains(String($0)) }
        } ?? parts.first ?? ""
        let cleaned = String(streetPart.map { $0.isLetter || $0.isNumber ? $0 : " " })
        var words = cleaned.split(separator: " ").map(String.init)
        words.removeAll { $0.contains(where: \.isNumber) }
        return words.map { abbreviations[$0] ?? $0 }.joined(separator: " ")
    }

    private static let streetWords: Set<String> = [
        "road", "rd", "street", "st", "avenue", "ave", "drive", "dr", "lane", "ln", "close", "cl", "crescent", "cres",
        "court", "ct", "place", "pl", "gardens", "gdns", "terrace", "terr", "way", "park", "grove", "hill", "view", "rise",
        "walk", "square", "mews", "parade", "lon", "ffordd", "heol", "stryd", "maes", "rhodfa", "llys", "cae", "bryn",
    ]

    /// The street as written, for showing: the street part of the address without house numbers ("Spring Gardens").
    static func streetName(_ address: String) -> String {
        let parts = address.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let streetPart = parts.first { part in
            part.contains(where: \.isNumber) || part.lowercased().split(whereSeparator: { !$0.isLetter }).contains { streetWords.contains(String($0)) }
        } ?? parts.first ?? ""
        let skip: Set<String> = ["unit", "flat", "apartment", "apt", "no"]
        let words = streetPart.split(separator: " ").filter { !$0.contains(where: \.isNumber) && !skip.contains($0.lowercased()) }
        let name = words.joined(separator: " ")
        return name.isEmpty ? address : name
    }

    /// "Rd" and "Road" are the same street.
    private static let abbreviations: [String: String] = [
        "rd": "road", "st": "street", "ave": "avenue", "av": "avenue", "dr": "drive", "ln": "lane", "cl": "close",
        "cres": "crescent", "ct": "court", "pl": "place", "gdns": "gardens", "gdn": "gardens", "terr": "terrace",
        "ter": "terrace", "sq": "square", "pk": "park", "gr": "grove",
    ]

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
