import Foundation

public struct TranslationItem: Sendable, Equatable {
    public let id: Int
    public let english: String

    public init(id: Int, english: String) {
        self.id = id
        self.english = english
    }
}

public struct ContextPair: Sendable, Equatable {
    public let english: String
    public let korean: String

    public init(english: String, korean: String) {
        self.english = english
        self.korean = korean
    }
}

public enum PromptBuilder {
    public static func systemPrompt(glossary: Glossary) -> String {
        let terms = glossary.entries
            .map { "- \($0.english[0]) → \($0.korean[0])" }
            .joined(separator: "\n")
        return """
        당신은 미국 기업 실적 발표(earnings call)를 한국어로 옮기는 전문 금융 번역가입니다.
        영어 문장을 자연스러운 한국어로 번역하되, 숫자와 재무 용어는 정확해야 합니다.

        규칙:
        1. 숫자는 한국어 단위로 정확히 환산하세요. billion은 10억, trillion은 1조입니다. 예: $94.9 billion → 949억 달러, $1.2 trillion → 1조 2,000억 달러.
        2. %, bp, %p 는 그대로 유지하세요. basis points → bp, percentage points → %p.
        3. 분기와 회계연도: Q3 → 3분기, first quarter → 1분기, FY2026 → 2026 회계연도.
        4. 통화를 바꾸지 마세요. 달러는 달러, 유로는 유로입니다.
        5. 말하지 않은 숫자를 추가하지 마세요. 원문에 있는 숫자는 하나도 빠뜨리지 마세요.
        6. 모든 문장을 한국어로 번역하세요. 설명이나 주석 없이 번역문만 출력하세요. 회사명과 제품명은 영어 그대로 둘 수 있습니다.
        7. 아래 용어집의 번역어를 사용하세요.

        용어집:
        \(terms)

        출력 형식: {"translations":[{"id":번호,"ko":"번역문"}]} — 입력의 모든 번호에 대해 하나씩 답하세요.
        """
    }

    public static func userMessage(items: [TranslationItem], context: [ContextPair], hints: [ValidationIssue]) -> String {
        var parts: [String] = []
        if !context.isEmpty {
            let lines = context.map { "EN: \($0.english)\nKO: \($0.korean)" }.joined(separator: "\n")
            parts.append("이전 문맥 (번역하지 마세요):\n\(lines)")
        }
        parts.append("번역할 문장:\n" + items.map { "[\($0.id)] \($0.english)" }.joined(separator: "\n"))
        if !hints.isEmpty {
            parts.append("주의 (이전 번역의 문제):\n" + hints.map { "- \(hint($0))" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    public static var responseSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "translations": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": ["id": ["type": "integer"], "ko": ["type": "string"]],
                        "required": ["id", "ko"],
                    ],
                ],
            ],
            "required": ["translations"],
        ]
    }

    private static func hint(_ issue: ValidationIssue) -> String {
        switch issue {
        case .missingQuantity(let quantity): return "원문의 \(quantity) 값이 번역에 없습니다."
        case .extraQuantity(let quantity): return "원문에 없는 \(quantity) 값이 번역에 있습니다."
        case .missingTerm(let entry): return "'\(entry.english[0])'는 '\(entry.korean[0])'(으)로 번역하세요."
        case .emptyTranslation: return "번역이 비어 있었습니다."
        case .untranslatedEnglish: return "영어를 남기지 말고 한국어로 번역하세요."
        }
    }
}
