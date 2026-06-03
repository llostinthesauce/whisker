import Foundation

/// Reads and writes HandoffResult to the App Group shared container.
/// Used by both the main app (writer) and the keyboard extension (reader).
enum HandoffService {

    static let appGroupIdentifier = "group.app.whisker"

    private static let handoffDirectory = "handoff"
    private static let resultFilename = "result.json"
    private static let commandFilename = "command.json"

    // MARK: - Container

    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }

    static var resultFileURL: URL? {
        containerURL?
            .appendingPathComponent(handoffDirectory, isDirectory: true)
            .appendingPathComponent(resultFilename)
    }

    static var commandFileURL: URL? {
        containerURL?
            .appendingPathComponent(handoffDirectory, isDirectory: true)
            .appendingPathComponent(commandFilename)
    }

    // MARK: - Write (main app)

    /// Writes the result file. `signal` rings the keyboard's `.result` doorbell;
    /// pass `false` for the keyboard's own cold-launch write, which only the app
    /// reads on launch and would otherwise wake the keyboard's own observer.
    static func writeResult(_ result: HandoffResult, signal: Bool = true) throws {
        guard let fileURL = resultFileURL else {
            throw HandoffError.appGroupUnavailable
        }

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(result)
        try data.write(to: fileURL, options: .atomic)
        if signal {
            HandoffSignal.post(.result)
        }
    }

    static func writeStatus(
        _ status: HandoffResult.HandoffStatus,
        backend: String = "",
        elapsedSeconds: Double? = nil,
        maxDurationSeconds: Double? = nil
    ) throws {
        let result = HandoffResult(
            text: "",
            timestamp: Date(),
            backend: backend,
            status: status,
            elapsedSeconds: elapsedSeconds,
            maxDurationSeconds: maxDurationSeconds
        )
        try writeResult(result)
    }

    static func writeKeyboardRecordRequest() throws {
        let result = HandoffResult(
            text: "",
            timestamp: Date(),
            backend: "Keyboard",
            status: .pending
        )
        try writeResult(result, signal: false)
    }

    // MARK: - Commands (extension writer, main app reader)

    static func writeKeyboardCommand(_ action: HandoffCommand.Action) throws {
        try writeCommand(HandoffCommand(action: action))
    }

    static func writeCommand(_ command: HandoffCommand) throws {
        guard let fileURL = commandFileURL else {
            throw HandoffError.appGroupUnavailable
        }

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(command)
        try data.write(to: fileURL, options: .atomic)
        HandoffSignal.post(.command)
    }

    static func readCommand() -> HandoffCommand? {
        guard let fileURL = commandFileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(HandoffCommand.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Read (extension)

    static func readResult() -> HandoffResult? {
        guard let fileURL = resultFileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(HandoffResult.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Clear

    static func clearResult() {
        guard let fileURL = resultFileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func clearCommand() {
        guard let fileURL = commandFileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

enum HandoffError: Error, LocalizedError {
    case appGroupUnavailable

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "App Group container is not available. Check entitlements."
        }
    }
}
