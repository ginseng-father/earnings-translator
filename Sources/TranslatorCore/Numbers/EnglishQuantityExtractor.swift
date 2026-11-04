import Foundation

public enum EnglishQuantityExtractor {
    private static let ordinals = ["first": 1, "second": 2, "third": 3, "fourth": 4]
    private static let units = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9,
    ]

    // Alternatives are tried left to right at each position, so quarter and
    // fiscal-year phrases win over the bare number inside them.
    private static let pattern = try! NSRegularExpression(
        pattern: #"""
        \bQ(?<q>[1-4])\b
        |\b(?<ordinal>first|second|third|fourth)\s+quarter\b
        |\b(?:FY|fiscal(?:\s+year)?)\s*'?(?<fy>\d{4}|\d{2})\b
        |\bfiscal(?:\s+year)?\s+twenty(?:[-\s](?<fyword>one|two|three|four|five|six|seven|eight|nine))?\b
        |\$?(?<num>\d[\d,]*(?:\.\d+)?)(?:\s*(?<unit>%|(?:trillion|billion|million|thousand|percentage\s+points?|percent|basis\s+points?|bps?)\b))?
        """#,
        options: [.caseInsensitive, .allowCommentsAndWhitespace]
    )

    public static func extract(_ text: String) -> [Quantity] {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).compactMap { match in
            func group(_ name: String) -> String? {
                let r = match.range(withName: name)
                guard r.location != NSNotFound, let swiftRange = Range(r, in: text) else { return nil }
                return String(text[swiftRange])
            }

            if let quarter = group("q") {
                return Quantity(Decimal(string: quarter)!, .quarter)
            }
            if let ordinal = group("ordinal") {
                return Quantity(Decimal(ordinals[ordinal.lowercased()]!), .quarter)
            }
            if let year = group("fy") {
                let value = Int(year)!
                return Quantity(Decimal(year.count == 2 ? 2000 + value : value), .fiscalYear)
            }
            if match.range(withName: "fyword").location != NSNotFound || group("num") == nil {
                let ones = group("fyword").map { units[$0.lowercased()]! } ?? 0
                return Quantity(Decimal(2020 + ones), .fiscalYear)
            }
            guard let digits = group("num"), let number = Decimal(digits: digits) else { return nil }
            return scaled(number, unit: group("unit"))
        }
    }

    private static func scaled(_ number: Decimal, unit: String?) -> Quantity {
        let word = unit?.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        switch word {
        case "trillion": return Quantity(number * 1_000_000_000_000, .plain)
        case "billion": return Quantity(number * 1_000_000_000, .plain)
        case "million": return Quantity(number * 1_000_000, .plain)
        case "thousand": return Quantity(number * 1_000, .plain)
        case "%", "percent": return Quantity(number, .percent)
        case "percentage point", "percentage points": return Quantity(number, .percentagePoints)
        case "basis point", "basis points", "bp", "bps": return Quantity(number, .basisPoints)
        default: return Quantity(number, .plain)
        }
    }
}
