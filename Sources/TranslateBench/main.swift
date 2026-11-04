import Foundation
import TranslatorCore

// Usage: TranslateBench <model> <fixtures.json>
// Translates each distinct fixture sentence singly, then in batches of 4,
// and reports latency and how many results fail validation.
struct Fixture: Decodable { let en: String }

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: TranslateBench <model> <fixtures.json>")
    exit(2)
}
let model = arguments[1]
let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
var seen = Set<String>()
let sentences = fixtures.map(\.en).filter { seen.insert($0).inserted }
let glossary = Glossary.standard
let client = OllamaClient(model: model, glossary: glossary)

func percentile(_ values: [Double], _ p: Double) -> Double {
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p + 0.5))]
}

func timed<T>(_ work: () async throws -> T) async rethrows -> (T, Double) {
    let start = ContinuousClock.now
    let value = try await work()
    let elapsed = ContinuousClock.now - start
    return (value, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
}

print("model: \(model), sentences: \(sentences.count)")
_ = try await client.translate([TranslationItem(id: 1, english: "Good afternoon.")], context: [], hints: [])

var singleLatency: [Double] = []
var flagged: [(String, String, [ValidationIssue])] = []
for sentence in sentences {
    let (reply, seconds) = try await timed { try await client.translate([TranslationItem(id: 1, english: sentence)], context: [], hints: []) }
    singleLatency.append(seconds)
    let korean = reply[1] ?? ""
    let issues = TranslationValidator.validate(english: sentence, korean: korean, glossary: glossary)
    if !issues.isEmpty { flagged.append((sentence, korean, issues)) }
}

var batchLatency: [Double] = []
var batchFlagged = 0
for start in stride(from: 0, to: sentences.count, by: 4) {
    let chunk = Array(sentences[start..<min(start + 4, sentences.count)])
    let items = chunk.enumerated().map { TranslationItem(id: $0.offset + 1, english: $0.element) }
    let (reply, seconds) = try await timed { try await client.translate(items, context: [], hints: []) }
    batchLatency.append(seconds)
    for item in items where !TranslationValidator.validate(english: item.english, korean: reply[item.id] ?? "", glossary: glossary).isEmpty {
        batchFlagged += 1
    }
}

print(String(format: "single: median %.2fs  p90 %.2fs  flagged %d/%d", percentile(singleLatency, 0.5), percentile(singleLatency, 0.9), flagged.count, sentences.count))
print(String(format: "batch4: median %.2fs  p90 %.2fs  flagged %d/%d", percentile(batchLatency, 0.5), percentile(batchLatency, 0.9), batchFlagged, sentences.count))
for (english, korean, issues) in flagged {
    print("FLAGGED: \(english)\n   → \(korean)\n   \(issues)")
}
