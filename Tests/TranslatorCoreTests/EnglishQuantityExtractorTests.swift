import Testing
@testable import TranslatorCore

struct EnglishQuantityExtractorTests {
    func extract(_ text: String) -> [Quantity] { EnglishQuantityExtractor.extract(text) }

    @Test func revenueAndPercent() {
        #expect(extract("Revenue was $94.9 billion, up 6% year over year.") == [q("94900000000"), q("6", .percent)])
    }

    @Test func earningsPerShare() {
        #expect(extract("EPS of $1.64") == [q("1.64")])
    }

    @Test func basisPoints() {
        #expect(extract("margin expanded 120 basis points") == [q("120", .basisPoints)])
        #expect(extract("up 120 bps") == [q("120", .basisPoints)])
    }

    @Test func percentagePoints() {
        #expect(extract("up 2.5 percentage points") == [q("2.5", .percentagePoints)])
    }

    @Test func quarters() {
        #expect(extract("Q3") == [q("3", .quarter)])
        #expect(extract("in the third quarter") == [q("3", .quarter)])
        #expect(extract("the first quarter") == [q("1", .quarter)])
        #expect(extract("Fourth quarter revenue") == [q("4", .quarter)])
    }

    @Test func fiscalYears() {
        for text in ["fiscal 2026", "FY26", "fiscal '26", "fiscal twenty-six", "fiscal year 2026", "FY2026"] {
            #expect(extract(text) == [q("2026", .fiscalYear)], "\(text)")
        }
    }

    @Test func scaleWords() {
        #expect(extract("1,250 million") == [q("1250000000")])
        #expect(extract("$3.2 trillion") == [q("3200000000000")])
        #expect(extract("450 thousand units") == [q("450000")])
    }

    @Test func extractsRangeBothEnds() {
        #expect(extract("$1.60 to $1.65") == [q("1.60"), q("1.65")])
    }

    @Test func repeatedValuesAreCounted() {
        #expect(extract("3% and then 3%") == [q("3", .percent), q("3", .percent)])
    }

    @Test func signWordsIgnored() {
        #expect(extract("down 3%") == [q("3", .percent)])
    }

    @Test func plainYear() {
        #expect(extract("in 2025") == [q("2025")])
    }

    @Test func sentenceEndingPeriodIsNotDecimal() {
        #expect(extract("It grew 6 percent.") == [q("6", .percent)])
    }

    @Test func ordinalsAreNotQuantities() {
        // "for the 1st time" is usually rendered "처음으로", without a digit.
        #expect(extract("Has arrived on Mac for the 1st time") == [])
        #expect(extract("our 2nd and 3rd largest markets, 4th straight record") == [])
        #expect(extract("the 21st consecutive quarter") == [])
    }

    @Test func numericOrdinalQuarters() {
        #expect(extract("our 4th quarter results") == [q("4", .quarter)])
        #expect(extract("in the 1st quarter") == [q("1", .quarter)])
    }

    @Test func rangeCarriesTrailingUnitBack() {
        #expect(extract("grow between 7 and 10% year over year") == [q("7", .percent), q("10", .percent)])
        #expect(extract("7 to 10 percent") == [q("7", .percent), q("10", .percent)])
        #expect(extract("between 40 and 60 basis points") == [q("40", .basisPoints), q("60", .basisPoints)])
        #expect(extract("$1.5 to 2 billion") == [q("1500000000"), q("2000000000")])
    }

    @Test func pluralRoundNumbersAreNotQuantities() {
        #expect(extract("across 100s of stores") == [])
        #expect(extract("1000s of suppliers") == [])
    }
}
