import Foundation
import Testing
@testable import TranslatorCore

struct SegmentPresentationTests {
    func text(_ status: SegmentStatus, korean: String?, active: Bool) -> String {
        SegmentPresentation.koreanText(Segment(start: 0, english: "x", korean: korean, status: status), sessionActive: active).text
    }

    @Test func flaggedWithoutTextSaysNoTranslation() {
        #expect(text(.flagged([.emptyTranslation]), korean: nil, active: true) == "(번역 없음)")
    }

    @Test func waitingRowsDependOnSession() {
        #expect(text(.translating, korean: nil, active: true) == "번역 중…")
        #expect(text(.pending, korean: nil, active: false) == "(번역 대기 중 — 중단됨)")
    }

    @Test func translatedTextIsShown() {
        let shown = SegmentPresentation.koreanText(Segment(start: 0, english: "x", korean: "번역", status: .done), sessionActive: false)
        #expect(shown.text == "번역")
        #expect(!shown.isPlaceholder)
    }
}

struct SessionGateTests {
    @Test func startAndStopAreExclusive() {
        var gate = SessionGate()
        do { let ok = gate.beginStart(); #expect(ok) }
        do { let ok = gate.beginStart(); #expect(!ok) }   // a second press while starting is ignored
        do { let ok = gate.beginStop(); #expect(!ok) }    // cannot stop until start finished
        gate.finishStart(running: true)
        #expect(gate.phase == .running)
        do { let ok = gate.beginStop(); #expect(ok) }
        do { let ok = gate.beginStart(); #expect(!ok) }   // cannot start while stopping
        do { let ok = gate.beginStop(); #expect(!ok) }
        gate.finishStop()
        #expect(gate.phase == .idle)
        do { let ok = gate.beginStart(); #expect(ok) }
    }

    @Test func failedStartReturnsToIdle() {
        var gate = SessionGate()
        do { let ok = gate.beginStart(); #expect(ok) }
        gate.finishStart(running: false)
        #expect(gate.phase == .idle)
    }
}

struct StallDetectorTests {
    @Test func stallsAfterTimeoutWithoutFeed() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var detector = StallDetector(timeout: 10, startedAt: t0)
        #expect(!detector.isStalled(now: t0.addingTimeInterval(9)))
        #expect(detector.isStalled(now: t0.addingTimeInterval(11)))
        detector.feed(at: t0.addingTimeInterval(11))
        #expect(!detector.isStalled(now: t0.addingTimeInterval(20)))
        #expect(detector.isStalled(now: t0.addingTimeInterval(22)))
    }
}
