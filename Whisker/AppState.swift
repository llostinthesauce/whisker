import Foundation
import UIKit

enum EngineAvailability: Equatable {
    case notChecked
    case checking
    case ready
    case unavailable(reason: String)
}

@MainActor
final class AppState: ObservableObject {
    private(set) var dictationProcessor: any DictationProcessor
    let historyStore: HistoryStore
    let clipboardService: ClipboardService
    let permissions: PermissionsService

    @Published private(set) var engineAvailability: EngineAvailability = .notChecked
    @Published private(set) var processingConfigurationRevision = 0
    @Published private(set) var keyboardSessionStartRequestID: UUID?
    @Published var handoffMode: HandoffMode = .none

    enum HandoffMode: Equatable {
        case none
        case pendingRecord
        case recording
        case transcribing
        case completed
    }

    init() {
        dictationProcessor = Self.resolveProcessor()
        historyStore = HistoryStore()
        clipboardService = ClipboardService()
        permissions = PermissionsService()
    }

    func reloadProcessingConfiguration(resetAvailability: Bool = false) {
        dictationProcessor.cancel()
        dictationProcessor = Self.resolveProcessor()
        processingConfigurationRevision += 1
        if resetAvailability {
            engineAvailability = .notChecked
        }
    }

    func checkEngineAvailability(showChecking: Bool = true) async {
        guard permissions.mic == .granted else {
            engineAvailability = .notChecked
            return
        }

        if engineAvailability == .checking {
            return
        }
        if showChecking || engineAvailability != .ready {
            engineAvailability = .checking
        }
        do {
            try await dictationProcessor.prepare()
            engineAvailability = .ready
        } catch let TranscriptionError.engineUnavailable(reason) {
            engineAvailability = .unavailable(reason: reason)
        } catch {
            engineAvailability = .unavailable(reason: error.localizedDescription)
        }
    }

    func resetEngineAvailability() {
        engineAvailability = .notChecked
    }

    // MARK: - Extension Handoff

    func resumePendingKeyboardHandoffIfNeeded() {
        guard case .none = handoffMode else { return }
        guard let result = HandoffService.readResult(),
              result.status == .pending,
              Date().timeIntervalSince(result.timestamp) <= 120 else {
            return
        }
        startHandoffRecording()
    }

    func requestKeyboardSessionStart() {
        handoffMode = .none
        keyboardSessionStartRequestID = UUID()
    }

    func startHandoffRecording() {
        HandoffService.clearResult()
        do {
            try HandoffService.writeStatus(.recording, backend: dictationProcessor.displayName)
        } catch {
            WLogger.transcription.error("Failed to write handoff recording status: \(error)")
        }
        handoffMode = .pendingRecord
    }

    func markHandoffRecording() {
        guard case .pendingRecord = handoffMode else { return }
        do {
            try HandoffService.writeStatus(.recording, backend: dictationProcessor.displayName)
        } catch {
            WLogger.transcription.error("Failed to write handoff recording status: \(error)")
        }
        handoffMode = .recording
    }

    func markHandoffTranscribing() {
        guard case .recording = handoffMode else { return }
        do {
            try HandoffService.writeStatus(.transcribing, backend: dictationProcessor.displayName)
        } catch {
            WLogger.transcription.error("Failed to write handoff transcribing status: \(error)")
        }
        handoffMode = .transcribing
    }

    func completeHandoff(text: String) {
        guard case .transcribing = handoffMode else { return }

        do {
            let result = HandoffResult(
                text: text,
                timestamp: Date(),
                backend: dictationProcessor.displayName,
                status: .ready
            )
            try HandoffService.writeResult(result)
            handoffMode = .completed
        } catch {
            WLogger.transcription.error("Failed to write handoff result: \(error)")
            handoffMode = .none
        }
    }

    func failHandoff(message: String) {
        do {
            let result = HandoffResult(
                text: message,
                timestamp: Date(),
                backend: dictationProcessor.displayName,
                status: .error
            )
            try HandoffService.writeResult(result)
        } catch {
            WLogger.transcription.error("Failed to write handoff error: \(error)")
        }
        handoffMode = .none
    }

    func cancelHandoff() {
        handoffMode = .none
        HandoffService.clearResult()
    }

    private static func resolveProcessor() -> any DictationProcessor {
        guard let configuration = RemoteMacSettings.currentConfiguration else {
            return UnavailableDictationProcessor(
                displayName: "Remote server",
                reason: "Server URL and bearer token are not configured."
            )
        }
        return RemoteMacProcessor(configuration: configuration)
    }
}
