import Testing
@testable import TranslatorCore

struct PromptBuilderTests {
    @Test func systemPromptCarriesEveryRule() {
        let prompt = PromptBuilder.systemPrompt(glossary: .standard)
        for rule in [
            "$94.9 billion → 949억 달러",
            "%, bp, %p",
            "Q3 → 3분기",
            "FY2026 → 2026 회계연도",
            "말하지 않은 숫자를 추가하지 마세요",
            "설명이나 주석 없이",
            "용어집",
        ] {
            #expect(prompt.contains(rule), "missing rule: \(rule)")
        }
    }

    @Test func systemPromptListsGlossary() {
        let prompt = PromptBuilder.systemPrompt(glossary: .standard)
        for entry in Glossary.standard.entries {
            #expect(prompt.contains("\(entry.english[0]) → \(entry.korean[0])"))
        }
    }

    @Test func userMessageOrdersContextThenItems() {
        let message = PromptBuilder.userMessage(
            items: [TranslationItem(id: 1, english: "Revenue grew."), TranslationItem(id: 2, english: "Thanks.")],
            context: [ContextPair(english: "Good afternoon.", korean: "안녕하세요.")],
            hints: []
        )
        let context = try! #require(message.range(of: "이전 문맥"))
        let first = try! #require(message.range(of: "[1] Revenue grew."))
        #expect(context.lowerBound < first.lowerBound)
        #expect(message.contains("[2] Thanks."))
        #expect(message.contains("안녕하세요."))
        #expect(!message.contains("주의"))
    }

    @Test func userMessageSpellsOutHints() {
        let message = PromptBuilder.userMessage(
            items: [TranslationItem(id: 1, english: "Revenue was $94.9 billion.")],
            context: [],
            hints: [.missingQuantity(q("94900000000")), .extraQuantity(q("9490000000"))]
        )
        #expect(message.contains("원문의 94900000000 값이 번역에 없습니다"))
        #expect(message.contains("원문에 없는 9490000000 값이 번역에 있습니다"))
        #expect(!message.contains("이전 문맥"))
    }
}
