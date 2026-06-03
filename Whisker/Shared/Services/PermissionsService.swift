import Foundation
import AVFoundation

enum MicPermission: Equatable {
    case notDetermined, granted, denied
}

@MainActor
final class PermissionsService: ObservableObject {
    @Published private(set) var mic: MicPermission = .notDetermined

    var allGranted: Bool { mic == .granted }

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        mic = currentMic()
    }

    func requestMic() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        mic = granted ? .granted : .denied
        WLogger.permissions.info("Mic permission: \(String(describing: self.mic))")
    }

    func requestAll() async {
        await requestMic()
    }

    private func currentMic() -> MicPermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .notDetermined
        }
    }
}
