import Foundation

/// Faithful port of `server/cleanup/rules.py`. The server owns cleanup
/// semantics; this mirror exists only so streaming joins cleaned on-device
/// produce the same text as the server's batch and whole-file-fallback paths.
/// Any behavior change must land in both implementations.
public struct RuleBasedCleaner: TextCleaner {
    public init() {}

    public func clean(_ input: String, mode: CleanupMode) async throws -> String {
        switch mode {
        case .raw:
            return input
        case .light:
            return normalizeWhitespace(input)
        case .message, .email:
            return sentenceStart(normalizeWhitespace(input))
        case .notes:
            return splitSentences(normalizeWhitespace(input)).joined(separator: "\n")
        case .bullets:
            return splitSentences(normalizeWhitespace(input))
                .map { "- \($0)" }
                .joined(separator: "\n")
        }
    }

    /// Mirrors `normalize_whitespace`: collapses runs of horizontal whitespace
    /// to one space, reduces 3+ newlines to a paragraph break, and trims.
    private func normalizeWhitespace(_ input: String) -> String {
        var text = input.replacingOccurrences(of: "\u{00A0}", with: " ")
        text = replacing(text, pattern: "[ \t\r\u{000B}\u{000C}]+", with: " ")
        text = replacing(text, pattern: "\\n{3,}", with: "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Mirrors `_sentence_start`: uppercases the first character only.
    private func sentenceStart(_ input: String) -> String {
        guard let first = input.first else { return input }
        return String(first).uppercased() + String(input.dropFirst())
    }

    /// Mirrors `_split_sentences`: splits after terminal punctuation and
    /// capitalizes each sentence.
    private func splitSentences(_ input: String) -> [String] {
        guard !input.isEmpty else { return [] }
        let sentences = split(input, separatorPattern: "(?<=[.!?])\\s+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(sentenceStart)
        return sentences.isEmpty ? [input] : sentences
    }

    private func replacing(_ input: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: template)
    }

    private func split(_ input: String, separatorPattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: separatorPattern) else {
            return [input]
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = regex.matches(in: input, range: range)
        guard !matches.isEmpty else { return [input] }

        var pieces: [String] = []
        var start = input.startIndex
        for match in matches {
            guard let separatorRange = Range(match.range, in: input) else { continue }
            pieces.append(String(input[start..<separatorRange.lowerBound]))
            start = separatorRange.upperBound
        }
        pieces.append(String(input[start...]))
        return pieces
    }
}
