import Foundation
import Testing
@testable import TranslatorCore

struct GlossaryTests {
    @Test func standardContainsRequiredEntries() {
        let required: [(String, String)] = [
            ("EPS", "주당순이익"), ("earnings per share", "주당순이익"),
            ("guidance", "가이던스"), ("outlook", "가이던스"),
            ("year over year", "전년 대비"), ("year-over-year", "전년 대비"),
            ("quarter over quarter", "전 분기 대비"), ("sequentially", "전 분기 대비"),
            ("operating margin", "영업이익률"), ("gross margin", "매출총이익률"),
            ("free cash flow", "잉여현금흐름"), ("headwind", "역풍"), ("tailwind", "순풍"),
            ("beat", "상회"), ("miss", "하회"), ("consensus", "컨센서스"),
            ("buyback", "자사주 매입"), ("share repurchase", "자사주 매입"),
            ("dividend", "배당"), ("revenue", "매출"), ("net income", "순이익"),
            ("operating income", "영업이익"), ("capex", "설비투자"), ("capital expenditures", "설비투자"),
            ("low-single digits", "한 자릿수 초반"), ("mid-single digits", "한 자릿수 중반"),
            ("high-single digits", "한 자릿수 후반"), ("double digits", "두 자릿수"),
        ]
        for (english, korean) in required {
            let entries = Glossary.standard.entries(presentIn: english)
            #expect(entries.contains { $0.korean.first == korean }, "\(english) → \(korean)")
        }
    }

    @Test func matchesCaseInsensitiveWithPlural() {
        let entries = Glossary.standard.entries(presentIn: "Headwinds persisted in Europe")
        #expect(entries.contains { $0.korean.first == "역풍" })
    }

    @Test func doesNotMatchInsideLongerWord() {
        let entries = Glossary.standard.entries(presentIn: "off the beaten path")
        #expect(!entries.contains { $0.korean.first == "상회" })
    }

    @Test func roundTripsThroughJSON() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("glossary-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Glossary.standard.save(to: url)
        #expect(try Glossary.load(from: url).entries == Glossary.standard.entries)
    }
}
