import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var permissions: PermissionsService
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding = false
    @State private var hasReachedRecorder = false

    var body: some View {
        Group {
            if let recovery = permissionRecoveryMessage {
                PermissionRecoveryView(message: recovery)
            } else if permissions.mic == .granted {
                NavigationStack {
                    engineContent
                }
            } else {
                NavigationStack {
                    RecorderView(appState: appState)
                }
            }
        }
        .sheet(isPresented: $showOnboarding) {
            PermissionsOnboardingView()
        }
        .onAppear(perform: refreshAppState)
        .onChange(of: permissions.mic) { _, _ in
            updatePermissionPresentation()
            checkEngineIfAllowed()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshAppState()
            }
        }
        .onChange(of: appState.engineAvailability) { _, availability in
            if availability == .ready {
                hasReachedRecorder = true
            }
        }
    }

    @ViewBuilder
    private var engineContent: some View {
        switch appState.engineAvailability {
        case .notChecked, .checking where !hasReachedRecorder:
            EngineCheckingView()
                .environmentObject(appState)
                .task {
                    await appState.checkEngineAvailability(showChecking: true)
                }
        case .unavailable(let reason) where !hasReachedRecorder:
            EngineUnavailableView(reason: reason)
        default:
            RecorderView(appState: appState)
                .onAppear {
                    hasReachedRecorder = true
                }
            }
    }

    private var permissionRecoveryMessage: String? {
        if permissions.mic == .denied {
            return "Microphone permission is denied. Open Settings and allow microphone access so whisker can record and send audio to your server."
        }
        return nil
    }

    private var needsOnboarding: Bool {
        permissions.mic == .notDetermined
    }

    private func refreshAppState() {
        permissions.refreshStatus()
        appState.historyStore.reload()
        appState.resumePendingKeyboardHandoffIfNeeded()
        updatePermissionPresentation()
        checkEngineIfAllowed()
    }

    private func updatePermissionPresentation() {
        showOnboarding = needsOnboarding
    }

    private func checkEngineIfAllowed() {
        guard permissions.mic == .granted else {
            appState.resetEngineAvailability()
            return
        }
        let showChecking = !hasReachedRecorder && appState.engineAvailability != .ready
        Task { await appState.checkEngineAvailability(showChecking: showChecking) }
    }
}

private struct EngineCheckingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(WhiskerTheme.pacific)
            Text("Checking transcription server...")
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WhiskerTheme.appBackground.ignoresSafeArea())
    }
}

private struct EngineUnavailableView: View {
    let reason: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "network.slash")
                .font(.system(size: 56))
                .foregroundStyle(WhiskerTheme.pacific)
            Text("Server unavailable")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(reason)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            NavigationLink {
                SettingsView()
            } label: {
                Label("Open Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WhiskerTheme.appBackground.ignoresSafeArea())
    }
}

private struct PermissionRecoveryView: View {
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.circle")
                .font(.system(size: 56))
                .foregroundStyle(WhiskerTheme.pacific)
            Text("Permission required")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WhiskerTheme.appBackground.ignoresSafeArea())
    }
}
