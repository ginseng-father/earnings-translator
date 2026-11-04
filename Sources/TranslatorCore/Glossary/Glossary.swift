import Foundation

public struct GlossaryEntry: Codable, Sendable, Hashable {
    /// English spellings that trigger the entry. Plurals (`s`/`es`) match automatically.
    public let english: [String]
    /// Accepted Korean renderings; the first is the one the prompt asks for.
    public let korean: [String]

    public init(english: [String], korean: [String]) {
        self.english = english
        self.korean = korean
    }

    func appears(in text: String) -> Bool {
        english.contains { term in
            let words = term.split(whereSeparator: { $0 == " " || $0 == "-" }).map { NSRegularExpression.escapedPattern(for: String($0)) }
            let pattern = #"\b"# + words.joined(separator: #"[\s-]+"#) + #"(?:s|es)?\b"#
            return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    /// Spacing-insensitive, since "전분기 대비" and "전 분기 대비" are both correct.
    func isRendered(in korean: String) -> Bool {
        let compact = korean.filter { !$0.isWhitespace }
        return self.korean.contains { compact.contains($0.filter { !$0.isWhitespace }) }
    }
}

public struct Glossary: Sendable {
    public let entries: [GlossaryEntry]

    public init(entries: [GlossaryEntry]) {
        self.entries = entries
    }

    public static let standard = Glossary(entries: [
        GlossaryEntry(english: ["EPS", "earnings per share"], korean: ["주당순이익", "EPS"]),
        GlossaryEntry(english: ["guidance"], korean: ["가이던스"]),
        GlossaryEntry(english: ["outlook"], korean: ["가이던스", "전망"]),
        GlossaryEntry(english: ["year over year", "year-over-year"], korean: ["전년 대비", "전년 동기 대비"]),
        GlossaryEntry(english: ["quarter over quarter", "quarter-over-quarter", "sequentially"], korean: ["전 분기 대비", "직전 분기 대비"]),
        GlossaryEntry(english: ["operating margin"], korean: ["영업이익률"]),
        GlossaryEntry(english: ["gross margin"], korean: ["매출총이익률", "총이익률"]),
        GlossaryEntry(english: ["free cash flow"], korean: ["잉여현금흐름"]),
        GlossaryEntry(english: ["headwind"], korean: ["역풍", "악재"]),
        GlossaryEntry(english: ["tailwind"], korean: ["순풍", "호재"]),
        GlossaryEntry(english: ["beat"], korean: ["상회", "웃돌"]),
        GlossaryEntry(english: ["miss"], korean: ["하회", "밑돌"]),
        GlossaryEntry(english: ["consensus"], korean: ["컨센서스", "시장 예상"]),
        GlossaryEntry(english: ["buyback", "share repurchase"], korean: ["자사주 매입"]),
        GlossaryEntry(english: ["dividend"], korean: ["배당"]),
        GlossaryEntry(english: ["revenue"], korean: ["매출", "수익"]),
        GlossaryEntry(english: ["net income"], korean: ["순이익"]),
        GlossaryEntry(english: ["operating income"], korean: ["영업이익"]),
        GlossaryEntry(english: ["capex", "capital expenditure"], korean: ["설비투자", "자본적 지출"]),
        GlossaryEntry(english: ["low-single digit", "low single digit"], korean: ["한 자릿수 초반"]),
        GlossaryEntry(english: ["mid-single digit", "mid single digit"], korean: ["한 자릿수 중반"]),
        GlossaryEntry(english: ["high-single digit", "high single digit"], korean: ["한 자릿수 후반"]),
        GlossaryEntry(english: ["double digit", "double-digit"], korean: ["두 자릿수"]),
    ])

    public static func load(from url: URL) throws -> Glossary {
        Glossary(entries: try JSONDecoder().decode([GlossaryEntry].self, from: Data(contentsOf: url)))
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(entries).write(to: url, options: .atomic)
    }

    public func entries(presentIn english: String) -> [GlossaryEntry] {
        entries.filter { $0.appears(in: english) }
    }
}
