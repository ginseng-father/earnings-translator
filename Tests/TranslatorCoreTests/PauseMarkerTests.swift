import Foundation
import Testing
@testable import TranslatorCore

func clock(_ hour: Int, _ minute: Int, _ second: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: hour, minute: minute, second: second))!
}

struct PauseMarkerTests {
    @Test func labelWithResume() {
        let marker = PauseMarker(pausedAt: clock(21, 15, 2), resumedAt: clock(21, 18, 40), afterSegment: 3)
        #expect(marker.label == "⏸ 21:15:02 정지 · 21:18:40 다시 시작 (3분 38초)")
    }

    @Test func labelWhileStillPaused() {
        #expect(PauseMarker(pausedAt: clock(21, 15, 2), afterSegment: 3).label == "⏸ 21:15:02 정지")
    }

    @Test func durationFormats() {
        #expect(PauseMarker(pausedAt: clock(9, 0, 0), resumedAt: clock(9, 0, 45), afterSegment: 0).label.hasSuffix("(45초)"))
        #expect(PauseMarker(pausedAt: clock(9, 0, 0), resumedAt: clock(10, 2, 5), afterSegment: 0).label.hasSuffix("(1시간 2분)"))
    }

    @Test func entriesInterleavePausesAfterTheirSegment() {
        let segments = (0..<4).map { Segment(start: TimeInterval($0), english: "s\($0)") }
        let first = PauseMarker(pausedAt: clock(9, 0, 0), resumedAt: clock(9, 1, 0), afterSegment: 2)
        let second = PauseMarker(pausedAt: clock(9, 5, 0), afterSegment: 4)
        let entries = TranscriptEntry.interleave(segments: segments, pauses: [first, second])
        let shape = entries.map { entry -> String in
            switch entry {
            case .segment(let s): return s.english
            case .pause: return "|"
            }
        }
        #expect(shape == ["s0", "s1", "|", "s2", "s3", "|"])
    }

    @Test func markdownShowsPauses() {
        let segments = [
            Segment(start: 5, english: "Before.", korean: "이전.", status: .done),
            Segment(start: 300, english: "After.", korean: "이후.", status: .done),
        ]
        let pause = PauseMarker(pausedAt: clock(18, 31, 0), resumedAt: clock(18, 34, 30), afterSegment: 1)
        let expected = """
        # 실적 발표 번역 — 2026-11-04 18:30

        **[00:00:05]** Before.
        > 이전.

        ---
        _⏸ 18:31:00 정지 · 18:34:30 다시 시작 (3분 30초)_

        **[00:05:00]** After.
        > 이후.

        """
        #expect(MarkdownExporter.render(segments: segments, pauses: [pause], sessionStart: sessionStart()) == expected)
    }
}
