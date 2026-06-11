import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var modelSettings = ModelSettings()
    @StateObject private var privacySettings = PrivacySettings()
    @StateObject private var remoteSettings = RemoteMacSettings()
    @State private var showDeleteConfirm = false
    @State private var remoteHealthMessage: String?
    @State private var isCheckingRemote = false
    @State private var availableModels = RemoteModelProfile.defaults

    var body: some View {
        Form {
            Section {
                TextField("Local server URL", text: $remoteSettings.baseURLString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Tailscale server URL", text: $remoteSettings.fallbackBaseURLString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Bearer token", text: $remoteSettings.bearerToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Picker("Timeout", selection: $remoteSettings.timeoutSeconds) {
                    ForEach(RemoteTimeoutPreset.all) { preset in
                        Text(preset.label).tag(preset.seconds)
                    }
                }

                Picker("Model", selection: $remoteSettings.selectedModelID) {
                    ForEach(availableModels) { model in
                        Text(model.label).tag(model.id)
                    }
                }

                if let selectedModel {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedModel.model)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selectedModel.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Picker("Default cleanup", selection: $modelSettings.defaultCleanupMode) {
                    ForEach(CleanupMode.implementedCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                Text(modelSettings.defaultCleanupMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    testRemoteConnection()
                } label: {
                    if isCheckingRemote {
                        Label("Checking", systemImage: "network")
                    } else {
                        Label("Test Server Connection", systemImage: "network")
                    }
                }
                .disabled(isCheckingRemote)

                Button {
                    applyRemoteSettings()
                } label: {
                    Label("Apply Server Settings", systemImage: "checkmark.circle")
                }

                if let remoteHealthMessage {
                    Text(remoteHealthMessage)
                        .font(.caption)
                        .foregroundStyle(remoteHealthMessage.hasPrefix("OK") ? .green : .red)
                }
            } header: {
                Text("Server")
            } footer: {
                Text("whisker tries the local URL first, then the Tailscale URL if the local server cannot connect or times out. Temporary audio stays on this iPhone until it is sent to your server.")
            }

            Section("Privacy") {
                Toggle("Save history", isOn: $privacySettings.saveHistory)
                Toggle("Auto-copy result", isOn: $privacySettings.autoCopyResult)
            }

            Section {
                NavigationLink {
                    KeyboardSetupView()
                } label: {
                    Label("Keyboard setup", systemImage: "keyboard")
                }
            } footer: {
                Text("Enable whisker in iOS Settings, turn on Allow Full Access, then keep a keyboard session running while using the keyboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                NavigationLink {
                    HistoryView(
                        historyStore: appState.historyStore,
                        clipboardService: appState.clipboardService
                    )
                } label: {
                    HistorySettingsRow(historyStore: appState.historyStore)
                }
            }

            Section {
                Button("Delete local history", role: .destructive) {
                    showDeleteConfirm = true
                }
            } footer: {
                Text("Temporary recordings are deleted after transcription. This clears saved transcript history only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(WhiskerTheme.appBackground.ignoresSafeArea())
        .tint(WhiskerTheme.pacific)
        .navigationTitle("settings")
        .confirmationDialog(
            "Delete local history?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                appState.historyStore.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .onChange(of: remoteSettings.timeoutSeconds) { _, _ in
            appState.reloadProcessingConfiguration(resetAvailability: true)
        }
        .onChange(of: remoteSettings.selectedModelID) { _, _ in
            appState.reloadProcessingConfiguration(resetAvailability: true)
        }
        .onChange(of: remoteSettings.baseURLString) { _, _ in
            appState.reloadProcessingConfiguration(resetAvailability: true)
        }
        .onChange(of: remoteSettings.fallbackBaseURLString) { _, _ in
            appState.reloadProcessingConfiguration(resetAvailability: true)
        }
        .onChange(of: remoteSettings.bearerToken) { _, _ in
            appState.reloadProcessingConfiguration(resetAvailability: true)
        }
    }

    private var selectedModel: RemoteModelProfile? {
        availableModels.first { $0.id == remoteSettings.selectedModelID }
    }

    private func testRemoteConnection() {
        guard let configuration = remoteSettings.configuration else {
            remoteHealthMessage = "Missing server URL or bearer token."
            return
        }

        isCheckingRemote = true
        remoteHealthMessage = nil
        Task {
            do {
                let health = try await RemoteMacClient(configuration: configuration).health()
                await MainActor.run {
                    isCheckingRemote = false
                    if !health.models.isEmpty {
                        availableModels = health.models
                    }
                    let selected = health.models.first { $0.id == remoteSettings.selectedModelID }
                    let selectedLabel = selected?.label ?? remoteSettings.selectedModelID
                    remoteHealthMessage = "OK: \(health.engine)/\(health.model) on \(health.server). Selected: \(selectedLabel)."
                }
            } catch {
                await MainActor.run {
                    isCheckingRemote = false
                    remoteHealthMessage = error.localizedDescription
                }
            }
        }
    }

    private func applyRemoteSettings() {
        appState.reloadProcessingConfiguration(resetAvailability: true)
        remoteHealthMessage = "Server settings applied."
        Task {
            await appState.checkEngineAvailability(showChecking: false)
        }
    }
}

private struct RemoteTimeoutPreset: Identifiable {
    let seconds: Double
    let label: String

    var id: Double { seconds }

    static let all: [RemoteTimeoutPreset] = [
        RemoteTimeoutPreset(seconds: 60, label: "1 minute"),
        RemoteTimeoutPreset(seconds: 300, label: "5 minutes")
    ]
}

private struct KeyboardSetupView: View {
    var body: some View {
        List {
            Section {
                KeyboardSetupStep(
                    number: 1,
                    title: "Enable whisker keyboard",
                    detail: "Open iOS Settings, add whisker, and turn on Allow Full Access."
                )
                KeyboardSetupStep(
                    number: 2,
                    title: "Start a keyboard session",
                    detail: "Open whisker from the keyboard to start a handoff session, then return to the text field."
                )
                KeyboardSetupStep(
                    number: 3,
                    title: "Dictate from any text field",
                    detail: "Switch to the whisker keyboard, tap Dictate to record, then tap again to stop and insert."
                )
            } footer: {
                Text("iOS does not allow third-party keyboards to record audio directly. whisker records in the main app, sends audio to your server, and passes the transcript back through the shared app container.")
            }

            Section {
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    Label("Open whisker Settings", systemImage: "gear")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(WhiskerTheme.appBackground.ignoresSafeArea())
        .navigationTitle("keyboard setup")
    }
}

private struct HistorySettingsRow: View {
    @ObservedObject var historyStore: HistoryStore

    var body: some View {
        Label {
            HStack {
                Text("Dictation history")
                Spacer()
                Text("\(historyStore.entries.count)")
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "clock.arrow.circlepath")
        }
    }
}

private struct HistoryView: View {
    @ObservedObject var historyStore: HistoryStore
    let clipboardService: ClipboardService

    var body: some View {
        List {
            if historyStore.entries.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock",
                    description: Text("Saved transcripts will appear here.")
                )
            } else {
                ForEach(historyStore.entries) { result in
                    HistoryEntryRow(result: result)
                        .swipeActions {
                            Button(role: .destructive) {
                                historyStore.delete(result)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                clipboardService.copy(result.displayText)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .tint(.blue)
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(WhiskerTheme.appBackground.ignoresSafeArea())
        .navigationTitle("history")
    }
}

private struct HistoryEntryRow: View {
    let result: DictationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.displayText)
                .lineLimit(3)

            HStack {
                Text(result.createdAt, format: .dateTime.month().day().hour().minute())
                Text(result.rawTranscript.engineName)
                Text("\(Int(result.rawTranscript.durationSeconds.rounded()))s")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct KeyboardSetupStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(WhiskerTheme.pacific))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
