import Foundation
import Testing
@testable import TranslatorCore

func sessionStart() -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 18, minute: 30))!
}

func sampleSegments() -> [Segment] {
    [
        Segment(start: 5, english: "Revenue was $94.9 billion.", korean: "매출은 949억 달러였습니다.", status: .done),
        Segment(start: 12, english: "Guidance was raised.", korean: "가이던스를 올렸습니다.", status: .flagged([.missingTerm(GlossaryEntry(english: ["x"], korean: ["y"]))])),
        Segment(start: 20, english: "Thank you.", status: .pending),
    ]
}

struct MarkdownExporterTests {
    @Test func rendersExactTranscript() {
        let expected = """
        # 실적 발표 번역 — 2026-11-04 18:30

        **[00:00:05]** Revenue was $94.9 billion.
        > 매출은 949억 달러였습니다.

        **[00:00:12]** Guidance was raised.
        > ⚠ 가이던스를 올렸습니다.

        **[00:00:20]** Thank you.
        > (번역 대기 중)

        """
        #expect(MarkdownExporter.render(segments: sampleSegments(), sessionStart: sessionStart()) == expected)
    }

    @Test func translatingRendersAsWaiting() {
        let segment = Segment(start: 3725, english: "Next question.", korean: nil, status: .translating)
        #expect(MarkdownExporter.render(segments: [segment], sessionStart: sessionStart()).contains("**[01:02:05]** Next question.\n> (번역 대기 중)"))
    }

    @Test func fileNameUsesSessionStart() {
        #expect(MarkdownExporter.fileName(for: sessionStart()) == "2026-11-04_1830.md")
    }
}
