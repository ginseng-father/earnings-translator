import Foundation

/// Currencies attached to amounts, named in Korean so both sides compare.
/// Only currency words next to a number count: "원" in 지원/직원 is not money.
enum CurrencyExtractor {
    static let order = ["달러", "유로", "파운드", "엔", "원", "센트"]

    private static let englishSymbols = try! NSRegularExpression(pattern: #"([$€£¥])\s?\d"#)
    private static let englishWords = try! NSRegularExpression(
        pattern: #"\d[\d,.]*\s*(?:(?:trillion|billion|million|thousand)\s+)?(dollars?|euros?|pounds?|yen|won|cents?)\b"#,
        options: [.caseInsensitive]
    )
    private static let korean = try! NSRegularExpression(pattern: #"\d[\d,.]*\s*(?:[조억만천]\s*)*(달러|유로|파운드|엔|원|센트)"#)

    private static let englishNames: [String: String] = [
        "$": "달러", "dollar": "달러", "dollars": "달러",
        "€": "유로", "euro": "유로", "euros": "유로",
        "£": "파운드", "pound": "파운드", "pounds": "파운드",
        "¥": "엔", "yen": "엔", "won": "원",
        "cent": "센트", "cents": "센트",
    ]

    static func english(_ text: String) -> Set<String> {
        Set(captures(englishSymbols, in: text) + captures(englishWords, in: text))
            .compactMap { englishNames[$0.lowercased()] }
            .reduce(into: []) { $0.insert($1) }
    }

    static func korean(_ text: String) -> Set<String> {
        Set(captures(korean, in: text))
    }

    static func sorted(_ currencies: Set<String>) -> [String] {
        order.filter(currencies.contains)
    }

    private static func captures(_ pattern: NSRegularExpression, in text: String) -> [String] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
