import SwiftUI

@main
struct DictationApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(appState.permissions)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == HandoffConstants.urlScheme else { return }

        switch HandoffLaunchAction.resolve(from: url) {
        case .keyboardSession:
            appState.requestKeyboardSessionStart()
        case .oneShotRecording:
            appState.startHandoffRecording()
        case nil:
            break
        }
    }
}
