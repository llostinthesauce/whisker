import SwiftUI

@main
struct DictationApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(appState.permissions)
                // The whisker palette is fixed light colors; without this,
                // dark mode flips system grays/materials against the light
                // gradient and contrast collapses.
                .preferredColorScheme(.light)
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
