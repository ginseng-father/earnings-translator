import Foundation

public enum KoreanQuantityExtractor {
    // One chunk: digits, an optional 천 multiplier, an optional big unit.
    // "5천만" = 5 × 1,000 × 10,000.
    private static let chunk = try! NSRegularExpression(
        pattern: #"(?<num>\d[\d,]*(?:\.\d+)?)(?<thousand>천)?(?<big>조|억|만)?"#
    )
    private static let suffix = try! NSRegularExpression(
        pattern: #"^\s*(?:(?<pp>%\s*p|%\s*포인트)|(?<pct>%)|(?<bp>bps?|베이시스\s*포인트)|(?<quarter>분기)|(?<fy>회계\s*연도))"#,
        options: [.caseInsensitive]
    )
    private static let bigScale: [String: Decimal] = ["조": 1_000_000_000_000, "억": 100_000_000, "만": 10_000]

    private struct Chunk {
        let value: Decimal
        let scale: Decimal?
        let range: Range<String.Index>
    }

    public static func extract(_ text: String) -> [Quantity] {
        let chunks = chunk.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> Chunk? in
            func group(_ name: String) -> String? {
                Range(match.range(withName: name), in: text).map { String(text[$0]) }
            }
            guard let digits = group("num"), var value = Decimal(digits: digits),
                  let range = Range(match.range, in: text) else { return nil }
            if group("thousand") != nil { value *= 1_000 }
            let scale = group("big").flatMap { bigScale[$0] }
            return Chunk(value: scale.map { value * $0 } ?? value, scale: scale, range: range)
        }

        var quantities: [Quantity] = []
        var index = 0
        while index < chunks.count {
            var total = chunks[index].value
            var end = chunks[index].range.upperBound
            var lastScale = chunks[index].scale
            // "1조 2,000억": a smaller big unit after whitespace continues the same number.
            while index + 1 < chunks.count,
                  let previous = lastScale,
                  let next = chunks[index + 1].scale, next < previous,
                  text[end..<chunks[index + 1].range.lowerBound].allSatisfy(\.isWhitespace) {
                index += 1
                total += chunks[index].value
                end = chunks[index].range.upperBound
                lastScale = next
            }
            quantities.append(Quantity(total, unit(after: end, in: text)))
            index += 1
        }
        return quantities
    }

    private static func unit(after end: String.Index, in text: String) -> QuantityUnit {
        let rest = String(text[end...])
        guard let match = suffix.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)) else { return .plain }
        func has(_ name: String) -> Bool { match.range(withName: name).location != NSNotFound }
        if has("pp") { return .percentagePoints }
        if has("pct") { return .percent }
        if has("bp") { return .basisPoints }
        if has("quarter") { return .quarter }
        if has("fy") { return .fiscalYear }
        return .plain
    }
}
