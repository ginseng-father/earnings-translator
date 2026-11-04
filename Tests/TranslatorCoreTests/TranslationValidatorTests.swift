import Foundation
import Testing
@testable import TranslatorCore

struct TranslationValidatorTests {
    func validate(_ english: String, _ korean: String) -> [ValidationIssue] {
        TranslationValidator.validate(english: english, korean: korean, glossary: .standard)
    }

    @Test func matchingTranslationHasNoIssues() {
        #expect(validate("Revenue was $94.9 billion, up 6% year over year.",
                         "매출은 949억 달러로 전년 대비 6% 증가했습니다.") == [])
    }

    @Test func wrongScaleIsReported() {
        #expect(validate("Revenue was $94.9 billion.", "매출은 94억 9천만 달러였습니다.")
            == [.missingQuantity(q("94900000000")), .extraQuantity(q("9490000000"))])
    }

    @Test func addedNumberIsReported() {
        #expect(validate("Revenue grew strongly.", "매출이 10% 증가했습니다.") == [.extraQuantity(q("10", .percent))])
    }

    @Test func missingTermIsReported() {
        let issues = validate("We are raising our guidance.", "전망을 상향합니다.")
        #expect(issues.count == 1)
        guard case .missingTerm(let entry) = issues.first else { Issue.record("expected missingTerm"); return }
        #expect(entry.korean.first == "가이던스")
    }

    @Test func emptyTranslationIsFlagged() {
        #expect(validate("Thank you.", "") == [.emptyTranslation])
        #expect(validate("Thank you.", "   \n") == [.emptyTranslation])
    }

    @Test func untranslatedEnglishIsReported() {
        #expect(validate("Thanks for joining us today.", "thanks for joining us today") == [.untranslatedEnglish])
    }

    @Test func properNounsAndAcronymsAreNotUntranslated() {
        #expect(validate("Microsoft Azure Cloud Services grew.", "Microsoft Azure Cloud Services 부문이 성장했습니다.") == [])
        #expect(validate("EPS was $1.64.", "주당순이익(EPS)은 1.64달러였습니다.") == [])
    }

    @Test func changedCurrencyIsReported() {
        #expect(validate("Revenue was $94.9 billion.", "매출은 949억 원이었습니다.")
            == [.currencyMismatch(expected: ["달러"], found: ["원"])])
        #expect(validate("Revenue was $94.9 billion.", "매출은 949억 유로였습니다.")
            == [.currencyMismatch(expected: ["달러"], found: ["유로"])])
    }

    @Test func sameCurrencyPasses() {
        #expect(validate("Revenue was 94.9 billion dollars.", "매출은 949억 달러였습니다.") == [])
        #expect(validate("Sales of €12 billion.", "120억 유로의 판매.") == [])
        #expect(validate("We now expect fiscal 2026 capex of $1.2 trillion won.", "2026 회계연도 설비투자는 1조 2,000억 원으로 예상합니다.") == [])
    }

    @Test func currencyWordsWithoutNumbersAreIgnored() {
        // "원" inside ordinary words (지원, 직원, 원활) is not a currency.
        #expect(validate("We support our employees.", "직원들을 지원합니다.") == [])
        #expect(validate("Revenue was $5 billion and support was smooth.", "매출은 50억 달러였고 지원은 원활했습니다.") == [])
    }

    @Test func missingCurrencyIsNotFlagged() {
        #expect(validate("EPS was $1.64.", "주당순이익(EPS)은 1.64였습니다.") == [])
        #expect(validate("Dividends were 3.9 billion.", "배당은 39억 달러였습니다.") == [])
    }

    struct FixtureCase: Decodable {
        let en: String
        let ko: String
        let expectedIssueCount: Int
    }

    @Test func fixtureSentences() throws {
        let url = try #require(Bundle.module.url(forResource: "earnings-sentences", withExtension: "json", subdirectory: "Fixtures"))
        let cases = try JSONDecoder().decode([FixtureCase].self, from: Data(contentsOf: url))
        #expect(cases.count >= 15)
        for item in cases {
            let issues = validate(item.en, item.ko)
            #expect(issues.count == item.expectedIssueCount, "\(item.en) → \(item.ko): \(issues)")
        }
    }
}
