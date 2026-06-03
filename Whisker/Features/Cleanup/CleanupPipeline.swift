import Foundation

public protocol TextCleaner: Sendable {
    func clean(_ input: String, mode: CleanupMode) async throws -> String
}

public final class CleanupPipeline: Sendable {
    private let cleaner: any TextCleaner

    public init(cleaner: any TextCleaner = RuleBasedCleaner()) {
        self.cleaner = cleaner
    }

    public func process(_ text: String, mode: CleanupMode) async throws -> String {
        guard mode != .raw else { return text }
        return try await cleaner.clean(text, mode: mode)
    }
}
