import Testing
@testable import TranslatorCore

struct KoreanQuantityExtractorTests {
    func extract(_ text: String) -> [Quantity] { KoreanQuantityExtractor.extract(text) }

    @Test func revenueAndPercent() {
        #expect(extract("매출은 949억 달러로 전년 대비 6% 증가") == [q("94900000000"), q("6", .percent)])
    }

    @Test func adjacentUnitsCombine() {
        #expect(extract("1조 2,000억 달러") == [q("1200000000000")])
        #expect(extract("3조 2천억") == [q("3200000000000")])
        #expect(extract("12억 5천만 달러") == [q("1250000000")])
    }

    @Test func earningsPerShare() {
        #expect(extract("주당순이익(EPS) 1.64달러") == [q("1.64")])
    }

    @Test func basisPoints() {
        #expect(extract("120bp 개선") == [q("120", .basisPoints)])
        #expect(extract("120 베이시스포인트") == [q("120", .basisPoints)])
    }

    @Test func percentagePoints() {
        #expect(extract("2.5%p 상승") == [q("2.5", .percentagePoints)])
        #expect(extract("2.5%포인트 상승") == [q("2.5", .percentagePoints)])
    }

    @Test func quarterAndFiscalYear() {
        #expect(extract("3분기 실적") == [q("3", .quarter)])
        #expect(extract("2026 회계연도") == [q("2026", .fiscalYear)])
        #expect(extract("2026회계연도") == [q("2026", .fiscalYear)])
    }

    @Test func extractsRangeBothEnds() {
        #expect(extract("1.60~1.65달러") == [q("1.60"), q("1.65")])
        #expect(extract("1.60달러에서 1.65달러") == [q("1.60"), q("1.65")])
    }

    @Test func plainYear() {
        #expect(extract("2025년") == [q("2025")])
    }

    @Test func repeatedValuesAreCounted() {
        #expect(extract("3%, 그리고 다시 3%") == [q("3", .percent), q("3", .percent)])
    }

    @Test func wrongScaleIsVisible() {
        #expect(extract("94억 9천만 달러") == [q("9490000000")])
    }

    @Test func monthNamesAreNotQuantities() {
        // English says "September", so a Korean "9월" must not count as an added number.
        #expect(extract("9월 분기 사상 최고치") == [])
        #expect(extract("9월 30일 기준") == [q("30")])
        #expect(extract("12개월 동안") == [q("12")])
    }
}
