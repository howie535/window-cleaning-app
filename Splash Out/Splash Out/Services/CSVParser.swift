import Foundation

enum CSVParser {
    /// Parses RFC 4180-ish CSV: quoted fields, doubled-quote escaping, commas/newlines inside quotes.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false

        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if insideQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 1
                    } else {
                        insideQuotes = false
                    }
                } else {
                    currentField.append(c)
                }
            } else if c == "\"" {
                insideQuotes = true
            } else if c == "," {
                currentRow.append(currentField)
                currentField = ""
            } else if c == "\n" || c == "\r" {
                if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" {
                    i += 1
                }
                currentRow.append(currentField)
                currentField = ""
                if !(currentRow.count == 1 && currentRow[0].isEmpty) {
                    rows.append(currentRow)
                }
                currentRow = []
            } else {
                currentField.append(c)
            }
            i += 1
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows
    }

    /// Strips currency symbols, commas, and whitespace so "£1,200.50" parses as a Decimal.
    static func parsePrice(_ raw: String) -> Decimal? {
        let cleaned = raw.filter { $0.isNumber || $0 == "." }
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned)
    }

    /// Pulls the first run of digits out of strings like "Every 5 weeks" or "5".
    static func parseFrequencyWeeks(_ raw: String) -> Int? {
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }
}
