import Foundation

public enum ValidationIssue: Sendable, Hashable {
    case missingQuantity(Quantity)
    case extraQuantity(Quantity)
    case missingTerm(GlossaryEntry)
    case emptyTranslation
    case untranslatedEnglish
}

public enum TranslationValidator {
    public static func validate(english: String, korean: String, glossary: Glossary) -> [ValidationIssue] {
        guard !korean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [.emptyTranslation] }

        let source = EnglishQuantityExtractor.extract(english)
        let target = KoreanQuantityExtractor.extract(korean)
        var issues = subtract(target, from: source).map(ValidationIssue.missingQuantity)
        issues += subtract(source, from: target).map(ValidationIssue.extraQuantity)
        issues += glossary.entries(presentIn: english)
            .filter { !$0.isRendered(in: korean) }
            .map(ValidationIssue.missingTerm)
        if looksUntranslated(korean) {
            issues.append(.untranslatedEnglish)
        }
        return issues
    }

    /// Multiset difference `values − other`, keeping the order of `values`.
    private static func subtract(_ other: [Quantity], from values: [Quantity]) -> [Quantity] {
        var available = Dictionary(other.map { ($0, 1) }, uniquingKeysWith: +)
        return values.filter { value in
            if let count = available[value], count > 0 {
                available[value] = count - 1
                return false
            }
            return true
        }
    }

    /// Four or more ASCII words in a row, at least two of them lowercase.
    /// Proper nouns ("Microsoft Azure Cloud Services") and acronyms stay legal.
    private static func looksUntranslated(_ korean: String) -> Bool {
        var run = 0
        var lowercase = 0
        for word in korean.split(whereSeparator: \.isWhitespace) {
            let letters = word.trimmingCharacters(in: .punctuationCharacters)
            if !letters.isEmpty, letters.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "'" || $0 == "-") }) {
                run += 1
                if letters.first!.isLowercase { lowercase += 1 }
                if run >= 4 && lowercase >= 2 { return true }
            } else {
                run = 0
                lowercase = 0
            }
        }
        return false
    }
}
