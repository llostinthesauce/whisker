import Foundation

public struct RuleBasedCleaner: TextCleaner {
    public init() {}

    public func clean(_ input: String, mode: CleanupMode) async throws -> String {
        switch mode {
        case .raw:
            return input
        case .light:
            return lightClean(input)
        case .message, .email:
            return formatSentence(lightClean(input))
        case .notes:
            return sentenceUnits(from: lightClean(input))
                .map(formatSentence)
                .joined(separator: "\n")
        case .bullets:
            let items = spokenNumberedItems(from: input)
            let bulletItems = items.isEmpty ? sentenceUnits(from: lightClean(input)) : items
            return bulletItems
                .map { "- \(formatSentence($0))" }
                .joined(separator: "\n")
        case .markdown, .concise:
            return input
        }
    }

    private func lightClean(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func formatSentence(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let capitalized = capitalizedFirstCharacter(trimmed)
        guard !hasTerminalPunctuation(capitalized) else { return capitalized }
        return capitalized + "."
    }

    private func capitalizedFirstCharacter(_ input: String) -> String {
        guard let first = input.first else { return input }
        let firstString = String(first)
        return firstString.uppercased() + String(input.dropFirst())
    }

    private func hasTerminalPunctuation(_ input: String) -> Bool {
        guard let last = input.last else { return false }
        return ".?!".contains(last)
    }

    private func sentenceUnits(from input: String) -> [String] {
        let normalized = lightClean(input)
        guard !normalized.isEmpty else { return [] }

        let pattern = #"(?<=[.!?])\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [normalized]
        }

        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = regex.matches(in: normalized, range: range)
        guard !matches.isEmpty else { return [normalized] }

        var units: [String] = []
        var start = normalized.startIndex
        for match in matches {
            guard let separatorRange = Range(match.range, in: normalized) else { continue }
            let unit = String(normalized[start..<separatorRange.lowerBound])
            units.append(unit)
            start = separatorRange.upperBound
        }
        units.append(String(normalized[start...]))

        return units
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func spokenNumberedItems(from input: String) -> [String] {
        let normalized = lightClean(input)
        let pattern = #"(?i)\bnumber\s+(one|two|three|four|five|six|seven|eight|nine|ten|\d+)\b\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsString = normalized as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: normalized, range: fullRange)
        guard matches.count >= 2 else { return [] }

        var items: [String] = []
        for index in matches.indices {
            let start = matches[index].range.location + matches[index].range.length
            let end = index + 1 < matches.count ? matches[index + 1].range.location : nsString.length
            guard end > start else { continue }
            let item = nsString.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !item.isEmpty {
                items.append(item)
            }
        }

        return items
    }
}
