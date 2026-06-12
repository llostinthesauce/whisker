import SwiftUI

struct RecorderView: View {
    @StateObject private var vm: TranscriptionViewModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var statusSnapshot = RecorderStatusSnapshot.current()
    @State private var handledKeyboardSessionStartRequestID: UUID?
    @ObservedObject private var historyStore: HistoryStore
    @State private var showStats = false

    init(appState: AppState) {
        _vm = StateObject(wrappedValue: TranscriptionViewModel(
            recorder: AudioRecorder(),
            processor: appState.dictationProcessor,
            historyStore: appState.historyStore,
            clipboard: appState.clipboardService
        ))
        _historyStore = ObservedObject(wrappedValue: appState.historyStore)
    }

    var body: some View {
        mainContent
            .background(WhiskerTheme.appBackground.ignoresSafeArea())
            .sheet(isPresented: $showStats) {
                StatsView(stats: historyStore.stats)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WhiskerWordmark(size: 32)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(WhiskerTheme.pacific)
                    }
                }
            }
            .onAppear {
                refreshStatusSnapshot()
                startKeyboardSessionIfRequested()
                startPendingHandoffIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in handleScenePhaseChange(phase) }
            .onChange(of: appState.keyboardSessionStartRequestID) { _, _ in
                startKeyboardSessionIfRequested()
            }
            .onChange(of: appState.handoffMode) { _, mode in
                if case .pendingRecord = mode {
                    startPendingHandoffIfNeeded()
                }
            }
            .onChange(of: vm.state) { _, state in
                handleStateChangeForHandoff(state)
            }
            .onChange(of: appState.engineAvailability) { _, _ in
                refreshStatusSnapshot()
            }
            .onChange(of: appState.processingConfigurationRevision) { _, _ in
                vm.setProcessor(appState.dictationProcessor)
                refreshStatusSnapshot()
            }
            .onChange(of: vm.keyboardSessionActive) { _, _ in
                refreshStatusSnapshot()
            }
            .onChange(of: vm.cleanupMode) { _, _ in
                refreshStatusSnapshot()
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            if isHandoffMode {
                handoffBanner
            } else if vm.keyboardSessionActive {
                keyboardSessionBanner
            }
            serverStatusRow
            statsStrip
            transcriptArea
            Divider()
                .overlay(WhiskerTheme.pacific.opacity(0.18))
            controlBar
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .active {
            refreshStatusSnapshot()
        } else if !isHandoffMode && !vm.keyboardSessionActive {
            vm.stopRecordingIfNeeded()
        }
    }

    private var isHandoffMode: Bool {
        if case .none = appState.handoffMode { return false }
        return true
    }

    private func startKeyboardSessionIfRequested() {
        guard let requestID = appState.keyboardSessionStartRequestID,
              handledKeyboardSessionStartRequestID != requestID else {
            return
        }
        handledKeyboardSessionStartRequestID = requestID
        vm.setKeyboardSessionActive(true)
        refreshStatusSnapshot()
    }

    private func startPendingHandoffIfNeeded() {
        guard case .pendingRecord = appState.handoffMode else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard case .pendingRecord = appState.handoffMode else { return }
            if vm.startRecordingIfPossible() {
                appState.markHandoffRecording()
            } else if case .failed(let message) = vm.state {
                appState.failHandoff(message: message)
            }
        }
    }

    private var handoffBanner: some View {
        HStack {
            Image(systemName: "keyboard.fill")
                .foregroundStyle(WhiskerTheme.pacific)
            if case .completed = appState.handoffMode {
                Text("done - switch back to insert")
                    .font(.caption.weight(.semibold))
            } else {
                Text("recording for keyboard")
                    .font(.caption.weight(.semibold))
            }
            Spacer()
            Button("cancel") {
                appState.cancelHandoff()
            }
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .foregroundStyle(WhiskerTheme.deepOcean)
        .background(WhiskerTheme.seaGlass.opacity(0.32))
    }

    private var keyboardSessionBanner: some View {
        HStack {
            Image(systemName: "keyboard.fill")
                .foregroundStyle(WhiskerTheme.kelp)
            Text("keyboard session on")
                .font(.caption.weight(.semibold))
            Spacer()
            Text(formatKeyboardSessionRemaining())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("stop") {
                vm.setKeyboardSessionActive(false)
            }
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .foregroundStyle(WhiskerTheme.deepOcean)
        .background(WhiskerTheme.foam.opacity(0.72))
    }

    private var serverStatusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(serverStatusColor)
                .frame(width: 8, height: 8)
            Text(serverStatusLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhiskerTheme.deepOcean)
            Spacer(minLength: 8)
            Text(statusSnapshot.serverLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(WhiskerTheme.foam.opacity(0.68))
    }

    private var statsStrip: some View {
        Button {
            showStats = true
        } label: {
            HStack(spacing: 0) {
                StatsStripTile(
                    value: historyStore.stats.totalWords.formatted(.number),
                    label: "words"
                )
                stripDivider
                StatsStripTile(
                    value: "\(historyStore.stats.transcriptionsToday)",
                    label: "today"
                )
                stripDivider
                StatsStripTile(
                    value: WhiskerStats.formatAudioDuration(historyStore.stats.totalAudioSeconds),
                    label: "audio"
                )
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WhiskerTheme.pacific.opacity(0.5))
                    .padding(.trailing, 14)
            }
            .frame(maxWidth: .infinity)
            .background(WhiskerTheme.foam.opacity(0.52))
            .overlay(alignment: .bottom) {
                Divider().overlay(WhiskerTheme.pacific.opacity(0.10))
            }
        }
        .buttonStyle(.plain)
    }

    private var stripDivider: some View {
        Divider()
            .frame(height: 28)
            .overlay(WhiskerTheme.pacific.opacity(0.15))
    }

    private var serverStatusLabel: String {
        switch appState.engineAvailability {
        case .ready:
            return "server ready"
        case .checking:
            return "checking server"
        case .unavailable:
            return "server unavailable"
        case .notChecked:
            return "server not checked"
        }
    }

    private var serverStatusColor: Color {
        switch appState.engineAvailability {
        case .ready:
            return WhiskerTheme.kelp
        case .checking:
            return WhiskerTheme.pacific
        case .unavailable:
            return WhiskerTheme.poppy
        case .notChecked:
            return .secondary
        }
    }

    private func handleStateChangeForHandoff(_ state: RecordingState) {
        guard isHandoffMode else { return }

        switch state {
        case .transcribing:
            appState.markHandoffTranscribing()

        case .finished(let result):
            appState.completeHandoff(text: result.displayText)

        case .failed(let message):
            appState.failHandoff(message: message)

        default:
            break
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var transcriptArea: some View {
        ScrollView {
            Group {
                switch vm.state {
                case .idle:
                    placeholderText("tap the button below to start recording.")

                case .recording:
                    VStack(spacing: 12) {
                        RecordingIndicator()
                        Text(formatElapsed(vm.elapsedSeconds))
                            .font(.system(.title3, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if !vm.liveTranscriptText.isEmpty {
                            Text(vm.liveTranscriptText)
                                .font(.title3)
                                .foregroundStyle(WhiskerTheme.deepOcean)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                                .textSelection(.enabled)
                                .padding(.top, 12)
                        }
                        if vm.elapsedSeconds >= recordingWarningThresholdSeconds {
                            Text("recording stops at \(formatElapsed(recordingMaxDurationSeconds))")
                                .font(.caption)
                                .foregroundStyle(WhiskerTheme.poppy)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)

                case .stopping, .transcribing:
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(WhiskerTheme.pacific)
                        Text("transcribing...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)

                case .finished(let result):
                    TranscriptTextView(result: result, mode: vm.cleanupMode)

                case .failed(let message):
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controlBar: some View {
        VStack(spacing: 16) {
            if case .finished = vm.state {
                HStack {
                    Text("cleanup: \(vm.cleanupMode.displayName.lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    copyButton
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }

            Button {
                vm.setKeyboardSessionActive(!vm.keyboardSessionActive)
            } label: {
                Label(
                    vm.keyboardSessionActive ? "stop keyboard session" : "start keyboard session",
                    systemImage: vm.keyboardSessionActive ? "keyboard.badge.eye" : "keyboard"
                )
                .frame(minWidth: 250)
            }
            .buttonStyle(CoastalPillButtonStyle(active: vm.keyboardSessionActive))
            .disabled(isKeyboardSessionToggleDisabled)

            RecordButton(state: vm.state) {
                vm.toggleRecording()
            }
            .padding(.bottom, 24)
        }
        .background(.ultraThinMaterial)
    }

    private var copyButton: some View {
        Button {
            vm.copyToClipboard()
        } label: {
            Label("copy", systemImage: "doc.on.doc")
        }
        .buttonStyle(CoastalPillButtonStyle())
    }

    // MARK: - Helpers

    private func placeholderText(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
    }

    private func formatElapsed(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var recordingMaxDurationSeconds: Double {
        RecordingLimits.maxDurationSeconds(keyboardSessionActive: vm.keyboardSessionActive)
    }

    private var recordingWarningThresholdSeconds: Double {
        RecordingLimits.warningThresholdSeconds(keyboardSessionActive: vm.keyboardSessionActive)
    }

    private var isKeyboardSessionToggleDisabled: Bool {
        switch vm.state {
        case .stopping, .transcribing:
            return true
        default:
            return false
        }
    }

    private func refreshStatusSnapshot() {
        statusSnapshot = RecorderStatusSnapshot.current()
    }

    private func formatKeyboardSessionRemaining() -> String {
        let seconds = vm.keyboardSessionRemainingSeconds
        let m = seconds / 60
        let s = seconds % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}

// MARK: - Sub-views

private struct RecordButton: View {
    let state: RecordingState
    let action: () -> Void

    private var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    private var isDisabled: Bool {
        switch state {
        case .stopping, .transcribing: return true
        default: return false
        }
    }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(isRecording ? WhiskerTheme.sunsetGradient : WhiskerTheme.aquaGradient)
                .frame(width: 72, height: 72)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.62), lineWidth: 2)
                }
                .overlay {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: WhiskerTheme.pacific.opacity(isRecording ? 0.18 : 0.30), radius: isRecording ? 12 : 16, y: 8)
                .scaleEffect(isRecording ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isRecording)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct RecordingIndicator: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(WhiskerTheme.poppy)
                .frame(width: 10, height: 10)
                .opacity(pulse ? 0.3 : 1.0)
                .animation(.easeInOut(duration: 0.7).repeatForever(), value: pulse)
            Text("recording")
                .font(.headline)
                .foregroundStyle(WhiskerTheme.poppy)
        }
        .onAppear { pulse = true }
    }
}

private struct TranscriptTextView: View {
    let result: DictationResult
    let mode: CleanupMode

    private var displayText: String {
        result.displayText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayText)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(result.rawTranscript.engineName) · \(String(format: "%.1f", result.rawTranscript.durationSeconds))s")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct StatsStripTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.bold))
                .foregroundStyle(WhiskerTheme.deepOcean)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

private struct RecorderStatusSnapshot: Equatable {
    let serverLabel: String
    let modelID: String
    let timeoutSeconds: Double

    var timeoutLabel: String {
        switch timeoutSeconds {
        case 60:
            return "1 min"
        case 300:
            return "5 min"
        default:
            return "\(Int(timeoutSeconds))s"
        }
    }

    static func current() -> RecorderStatusSnapshot {
        let defaults = UserDefaults.standard
        let rawURL = defaults.string(forKey: RemoteMacSettings.baseURLKey) ?? ""
        let rawFallbackURL = defaults.string(forKey: RemoteMacSettings.fallbackBaseURLKey) ?? ""
        let serverLabel = Self.serverLabel(localURLString: rawURL, fallbackURLString: rawFallbackURL)

        let timeout = RemoteMacSettings.normalizedTimeout(
            defaults.double(forKey: RemoteMacSettings.timeoutSecondsKey)
        )
        let modelID = defaults.string(forKey: RemoteMacSettings.selectedModelIDKey) ?? "balanced"

        return RecorderStatusSnapshot(
            serverLabel: serverLabel,
            modelID: modelID,
            timeoutSeconds: timeout
        )
    }

    private static func serverLabel(localURLString: String, fallbackURLString: String) -> String {
        let localHost = host(from: localURLString)
        let fallbackHost = host(from: fallbackURLString)

        switch (localHost, fallbackHost) {
        case (.some(let local), .some(let fallback)) where local != fallback:
            return "\(local) -> \(fallback)"
        case (.some(let host), _), (nil, .some(let host)):
            return host
        case (nil, nil):
            let hasLocal = !localURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasFallback = !fallbackURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasLocal || hasFallback ? "invalid URL" : "not configured"
        }
    }

    private static func host(from urlString: String) -> String? {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty,
              let url = URL(string: trimmedURL),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return host
    }
}
