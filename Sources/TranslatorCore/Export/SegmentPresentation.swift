import Foundation

/// What the transcript row shows in place of the Korean line.
public enum SegmentPresentation {
    public static func koreanText(_ segment: Segment, sessionActive: Bool) -> (text: String, isPlaceholder: Bool) {
        if let korean = segment.korean, !korean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (korean, false)
        }
        switch segment.status {
        case .flagged: return ("(번역 없음)", true)
        case .done: return ("(번역 없음)", true)
        case .pending, .translating: return (sessionActive ? "번역 중…" : "(번역 대기 중 — 중단됨)", true)
        }
    }
}
