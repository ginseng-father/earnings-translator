import Foundation

/// Breaks an over-long transcript result into translatable chunks of at most
/// `maxWords` words, cutting at the strongest punctuation available.
public enum SentenceSplitter {
    private static let boundaries: [Set<Character>] = [[".", "?", "!"], [";"], [","]]

    public static func split(_ text: String, maxWords: Int = 40) -> [String] {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > maxWords else { return [text] }

        var chunks: [String] = []
        while words.count > maxWords {
            let cut = cutIndex(in: words.prefix(maxWords)) ?? maxWords
            chunks.append(words[..<cut].joined(separator: " "))
            words.removeFirst(cut)
        }
        if !words.isEmpty {
            chunks.append(words.joined(separator: " "))
        }
        return chunks
    }

    /// Word count of the longest prefix ending at the highest-priority punctuation.
    private static func cutIndex(in window: ArraySlice<String>) -> Int? {
        for marks in boundaries {
            if let last = window.lastIndex(where: { $0.last.map(marks.contains) ?? false }) {
                return last + 1
            }
        }
        return nil
    }
}
