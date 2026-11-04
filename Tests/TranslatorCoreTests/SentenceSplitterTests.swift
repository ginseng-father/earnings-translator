import Testing
@testable import TranslatorCore

struct SentenceSplitterTests {
    func words(_ count: Int, from start: Int = 0) -> [String] { (start..<start + count).map { "w\($0)" } }
    func wordCounts(_ chunks: [String]) -> [Int] { chunks.map { $0.split(separator: " ").count } }

    @Test func shortTextIsUnchanged() {
        let text = "Revenue was $94.9 billion, up 6% year over year."
        #expect(SentenceSplitter.split(text) == [text])
    }

    @Test func splitsAtSentenceEndsFirst() {
        var all = words(90)
        all[29] += "."   // sentence ends after word 30
        all[59] += "?"   // and after word 60
        all[14] += ","   // a comma earlier must not win over the period
        let chunks = SentenceSplitter.split(all.joined(separator: " "))
        #expect(wordCounts(chunks) == [30, 30, 30])
    }

    @Test func prefersSemicolonOverComma() {
        var all = words(50)
        all[19] += ","
        all[34] += ";"
        let chunks = SentenceSplitter.split(all.joined(separator: " "))
        #expect(wordCounts(chunks) == [35, 15])
    }

    @Test func fallsBackToComma() {
        var all = words(50)
        all[24] += ","
        #expect(wordCounts(SentenceSplitter.split(all.joined(separator: " "))) == [25, 25])
    }

    @Test func hardSplitsWithoutBoundary() {
        #expect(wordCounts(SentenceSplitter.split(words(90).joined(separator: " "))) == [40, 40, 10])
    }

    @Test func preservesAllWordsInOrder() {
        var all = words(123)
        all[10] += "."; all[70] += ","; all[100] += ";"
        let text = all.joined(separator: "  \n")
        let chunks = SentenceSplitter.split(text)
        #expect(chunks.joined(separator: " ") == all.joined(separator: " "))
        #expect(chunks.allSatisfy { $0.split(separator: " ").count <= 40 })
    }
}
