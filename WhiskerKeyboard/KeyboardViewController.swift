import UIKit

@MainActor
class KeyboardViewController: UIInputViewController {

    // MARK: - State

    /// Identifier of the result we last consumed (timestamp acts as a unique cursor).
    /// Stored in App Group UserDefaults so it survives keyboard process restarts.
    private static let consumedTimestampKey = "whisker.keyboard.lastConsumedResultTimestamp"
    private static let liveStatusMaximumAge: TimeInterval = 8
    private static let pendingStatusMaximumAge: TimeInterval = 120

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: HandoffService.appGroupIdentifier)
    }

    private var transcriptRecovery: KeyboardTranscriptRecovery? {
        sharedDefaults.map(KeyboardTranscriptRecovery.init(defaults:))
    }

    // MARK: - UI

    private let dictateButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let nextKeyboardButton = UIButton(type: .system)
    private let reinsertButton = UIButton(type: .system)
    private let keyboardStack = UIStackView()
    private let shiftButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let spaceButton = UIButton(type: .system)
    private let returnButton = UIButton(type: .system)
    private var keyboardHeightConstraint: NSLayoutConstraint?
    private var statusPollTimer: Timer?
    private var lastKnownStatus: HandoffResult.HandoffStatus?
    private var liveTranscriptInserter = KeyboardLiveTranscriptInserter()
    private var letterKeys: [(button: UIButton, letter: String)] = []
    private var shiftEnabled = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateNextKeyboardButtonVisibility()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Each time the keyboard becomes visible (including returning from the
        // main app after a handoff), check for a pending transcript and insert.
        if !consumePendingResultIfReady() {
            updateUI(for: .idle)
        }
        updateReinsertButtonVisibility()
        startStatusPolling()
        HandoffSignal.observe(.result) { [weak self] in
            self?.consumePendingResultIfReady()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        statusPollTimer?.invalidate()
        statusPollTimer = nil
        HandoffSignal.stopObserving(.result)
    }

    // MARK: - Actions

    @objc private func dictateTapped() {
        guard hasFullAccess else { updateUI(for: .needsFullAccess); return }
        if lastKnownStatus == .standby {
            liveTranscriptInserter.reset()
            writeKeyboardCommand(.startRecording, fallbackState: .error("Could not start from keyboard"))
            updateUI(for: .starting)
            return
        }
        if lastKnownStatus == .recording {
            writeKeyboardCommand(.stopRecording, fallbackState: .error("Could not stop from keyboard"))
            updateUI(for: .waitingForApp(transcribing: true, elapsedSeconds: nil, maxDurationSeconds: nil))
            return
        }
        do {
            liveTranscriptInserter.reset()
            try HandoffService.writeKeyboardRecordRequest()
        } catch {
            updateUI(for: .error("Could not write keyboard request"))
            return
        }
        updateUI(for: .opening)
        openMainAppForRecording()
    }

    // MARK: - Open main app via responder chain

    private func openMainAppForRecording() {
        let url = HandoffConstants.recordURL
        if let extensionContext {
            extensionContext.open(url) { [weak self] success in
                Task { @MainActor in
                    if !success {
                        self?.openMainAppViaResponderChain(url)
                    }
                    self?.showManualOpenFallbackIfStillVisible()
                }
            }
            return
        }

        openMainAppViaResponderChain(url)
        showManualOpenFallbackIfStillVisible()
    }

    @objc private func keyTapped(_ sender: UIButton) {
        guard let letter = letterKeys.first(where: { $0.button === sender })?.letter else { return }
        textDocumentProxy.insertText(shiftEnabled ? letter.uppercased() : letter.lowercased())
        if shiftEnabled {
            shiftEnabled = false
            updateLetterCaps()
        }
    }

    @objc private func shiftTapped() {
        shiftEnabled.toggle()
        updateLetterCaps()
    }

    @objc private func deleteTapped() {
        textDocumentProxy.deleteBackward()
    }

    @objc private func spaceTapped() {
        textDocumentProxy.insertText(" ")
    }

    @objc private func returnTapped() {
        textDocumentProxy.insertText("\n")
    }

    @objc private func reinsertTapped() {
        guard let text = transcriptRecovery?.load() else {
            updateReinsertButtonVisibility()
            updateUI(for: .idle)
            return
        }
        textDocumentProxy.insertText(text)
        updateUI(for: .reinserted)
    }

    private func openMainAppViaResponderChain(_ url: URL) {
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
        updateUI(for: .error("Could not launch whisker app"))
    }

    private func showManualOpenFallbackIfStillVisible() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.view.window != nil else { return }
            self.updateUI(for: .openManually)
        }
    }

    // MARK: - Handoff result consumption

    private func startStatusPolling() {
        statusPollTimer?.invalidate()
        statusPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                _ = self?.consumePendingResultIfReady()
            }
        }
    }

    private func writeKeyboardCommand(_ action: HandoffCommand.Action, fallbackState: KeyboardState) {
        do {
            try HandoffService.writeKeyboardCommand(action)
        } catch {
            updateUI(for: fallbackState)
        }
    }

    /// Returns true if a result was inserted (so the caller skips the .idle reset).
    @discardableResult
    private func consumePendingResultIfReady() -> Bool {
        guard let result = HandoffService.readResult() else {
            lastKnownStatus = nil
            return false
        }
        guard !isStaleNonTerminalResult(result) else {
            lastKnownStatus = nil
            HandoffService.clearResult()
            return false
        }
        lastKnownStatus = result.status

        let resultTimestamp = result.timestamp.timeIntervalSince1970
        let lastConsumed = sharedDefaults?.double(forKey: Self.consumedTimestampKey) ?? 0

        switch result.status {
        case .pending:
            liveTranscriptInserter.reset()
            updateUI(for: .openManually)
            return true

        case .standby:
            updateUI(for: .standby)
            return true

        case .ready:
            // Skip results we have already inserted on a prior viewWillAppear.
            guard resultTimestamp > lastConsumed else { return false }
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            sharedDefaults?.set(resultTimestamp, forKey: Self.consumedTimestampKey)
            HandoffService.clearResult()
            lastKnownStatus = nil
            guard !text.isEmpty else {
                applyLiveTranscriptEdit(liveTranscriptInserter.finalize(with: ""))
                updateUI(for: .idle)
                return true
            }
            applyLiveTranscriptEdit(liveTranscriptInserter.finalize(with: text))
            transcriptRecovery?.save(text: text, timestamp: result.timestamp)
            updateUI(for: .inserted)
            updateReinsertButtonVisibility()
            return true

        case .error:
            guard resultTimestamp > lastConsumed else { return false }
            sharedDefaults?.set(resultTimestamp, forKey: Self.consumedTimestampKey)
            HandoffService.clearResult()
            lastKnownStatus = nil
            applyLiveTranscriptEdit(liveTranscriptInserter.finalize(with: ""))
            let message = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            updateUI(for: .error(message.isEmpty ? "whisker reported an error" : message))
            return true

        case .recording, .transcribing:
            // Main app is still working; show progress without consuming.
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                applyLiveTranscriptEdit(liveTranscriptInserter.updateLiveText(text))
            }
            updateUI(for: .waitingForApp(
                transcribing: result.status == .transcribing,
                elapsedSeconds: result.elapsedSeconds,
                maxDurationSeconds: result.maxDurationSeconds
            ))
            return true
        }
    }

    private func applyLiveTranscriptEdit(_ edit: KeyboardLiveTranscriptEdit?) {
        guard let edit else { return }
        if edit.deleteCharacterCount > 0 {
            for _ in 0..<edit.deleteCharacterCount {
                textDocumentProxy.deleteBackward()
            }
        }
        if !edit.insertText.isEmpty {
            textDocumentProxy.insertText(edit.insertText)
        }
    }

    private func isStaleNonTerminalResult(_ result: HandoffResult) -> Bool {
        let age = Date().timeIntervalSince(result.timestamp)
        switch result.status {
        case .pending:
            return age > Self.pendingStatusMaximumAge
        case .standby, .recording, .transcribing:
            return age > Self.liveStatusMaximumAge
        case .ready, .error:
            return false
        }
    }

    // MARK: - UI State

    private enum KeyboardState {
        case idle
        case standby
        case starting
        case opening
        case waitingForApp(transcribing: Bool, elapsedSeconds: Double?, maxDurationSeconds: Double?)
        case inserted
        case reinserted
        case error(String)
        case needsFullAccess
        case openManually
    }

    private func updateUI(for state: KeyboardState) {
        switch state {
        case .idle:
            statusLabel.text = "tap to dictate"
            statusLabel.textColor = .secondaryLabel
            dictateButton.isEnabled = true
            updateDictateButton(title: "dictate", imageName: "mic.fill")
        case .standby:
            statusLabel.text = "keyboard session ready"
            statusLabel.textColor = .systemGreen
            dictateButton.isEnabled = true
            updateDictateButton(title: "dictate", imageName: "mic.fill")
        case .starting:
            statusLabel.text = "starting recording..."
            statusLabel.textColor = .systemBlue
            dictateButton.isEnabled = false
            updateDictateButton(title: "dictate", imageName: "mic.fill")
        case .opening:
            statusLabel.text = "opening whisker..."
            statusLabel.textColor = .systemBlue
            dictateButton.isEnabled = false
            updateDictateButton(title: "dictate", imageName: "mic.fill")
        case .waitingForApp(let transcribing, let elapsedSeconds, let maxDurationSeconds):
            statusLabel.text = recordingStatusText(
                transcribing: transcribing,
                elapsedSeconds: elapsedSeconds,
                maxDurationSeconds: maxDurationSeconds
            )
            statusLabel.textColor = .systemBlue
            dictateButton.isEnabled = true
            updateDictateButton(title: transcribing ? "dictate" : "stop", imageName: transcribing ? "mic.fill" : "stop.fill")
        case .inserted:
            statusLabel.text = "inserted - tap undo arrow to reinsert"
            statusLabel.textColor = .systemGreen
            dictateButton.isEnabled = true
            updateDictateButton(title: "dictate", imageName: "mic.fill")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.updateUI(for: .idle)
            }
        case .reinserted:
            statusLabel.text = "reinserted"
            statusLabel.textColor = .systemGreen
            dictateButton.isEnabled = true
            updateDictateButton(title: "dictate", imageName: "mic.fill")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.updateUI(for: .idle)
            }
        case .error(let msg):
            statusLabel.text = msg
            statusLabel.textColor = .systemRed
            dictateButton.isEnabled = true
            updateDictateButton(title: "dictate", imageName: "mic.fill")
        case .needsFullAccess:
            statusLabel.text = "enable Full Access in iOS keyboard settings"
            statusLabel.textColor = .systemOrange
            dictateButton.isEnabled = true
            updateDictateButton(title: "dictate", imageName: "mic.fill")
        case .openManually:
            statusLabel.text = "open whisker to record, then return here"
            statusLabel.textColor = .systemOrange
            dictateButton.isEnabled = true
            updateDictateButton(title: "dictate", imageName: "mic.fill")
        }
    }

    private func recordingStatusText(
        transcribing: Bool,
        elapsedSeconds: Double?,
        maxDurationSeconds: Double?
    ) -> String {
        let prefix = transcribing ? "transcribing" : "recording"
        guard let elapsedSeconds else { return "\(prefix)..." }

        let elapsed = formatDuration(elapsedSeconds)
        if let maxDurationSeconds {
            return "\(prefix) \(elapsed) / \(formatDuration(maxDurationSeconds))"
        }
        return "\(prefix) \(elapsed)"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let wholeSeconds = max(0, Int(seconds))
        let minutes = wholeSeconds / 60
        let seconds = wholeSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private func updateDictateButton(title: String, imageName: String) {
        var config = dictateButton.configuration ?? UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(systemName: imageName)
        config.imagePadding = 8
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22)
        config.background.cornerRadius = 19
        config.background.backgroundColor = KeyboardPalette.keyBackground(traitCollection)
        config.baseForegroundColor = title == "stop"
            ? KeyboardPalette.stopTint
            : KeyboardPalette.oceanTint
        dictateButton.configuration = config
        dictateButton.layer.cornerRadius = 19
        dictateButton.layer.shadowColor = UIColor.black.cgColor
        dictateButton.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.22 : 0.14
        dictateButton.layer.shadowRadius = 5
        dictateButton.layer.shadowOffset = CGSize(width: 0, height: 2)
    }

    // MARK: - Layout

    private func setupUI() {
        guard let inputView = inputView else { return }
        inputView.allowsSelfSizing = true
        applyKeyboardChrome()

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        inputView.addSubview(container)

        updateDictateButton(title: "dictate", imageName: "mic.fill")
        dictateButton.addTarget(self, action: #selector(dictateTapped), for: .touchUpInside)
        dictateButton.translatesAutoresizingMaskIntoConstraints = false
        dictateButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let nextConfig = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
        nextKeyboardButton.setImage(UIImage(systemName: "globe", withConfiguration: nextConfig), for: .normal)
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        styleNextKeyboardButton()
        updateNextKeyboardButtonVisibility()

        reinsertButton.setImage(UIImage(systemName: "arrow.uturn.backward", withConfiguration: nextConfig), for: .normal)
        reinsertButton.accessibilityLabel = "Reinsert last dictation"
        reinsertButton.addTarget(self, action: #selector(reinsertTapped), for: .touchUpInside)
        reinsertButton.translatesAutoresizingMaskIntoConstraints = false
        styleReinsertButton()
        updateReinsertButtonVisibility()

        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.text = "tap to dictate"
        statusLabel.numberOfLines = 3
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let headerStack = UIStackView(arrangedSubviews: [
            nextKeyboardButton,
            statusLabel,
            reinsertButton,
            dictateButton
        ])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 8
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        keyboardStack.axis = .vertical
        keyboardStack.alignment = .fill
        keyboardStack.distribution = .fillEqually
        keyboardStack.spacing = 7
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false

        keyboardStack.addArrangedSubview(makeLetterRow(["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]))
        keyboardStack.addArrangedSubview(makeLetterRow(["a", "s", "d", "f", "g", "h", "j", "k", "l"], horizontalInset: 18))
        keyboardStack.addArrangedSubview(makeBottomLetterRow())
        keyboardStack.addArrangedSubview(makeCommandRow())

        container.addSubview(headerStack)
        container.addSubview(keyboardStack)

        let heightConstraint = container.heightAnchor.constraint(equalToConstant: 291)
        keyboardHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: inputView.topAnchor),
            container.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
            heightConstraint,

            headerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            headerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            headerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            headerStack.heightAnchor.constraint(equalToConstant: 44),

            nextKeyboardButton.widthAnchor.constraint(equalToConstant: 40),
            nextKeyboardButton.heightAnchor.constraint(equalToConstant: 40),
            reinsertButton.widthAnchor.constraint(equalToConstant: 40),
            reinsertButton.heightAnchor.constraint(equalToConstant: 40),
            dictateButton.heightAnchor.constraint(equalToConstant: 38),
            dictateButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 116),

            keyboardStack.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 8),
            keyboardStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            keyboardStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            keyboardStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
    }

    private func makeLetterRow(_ letters: [String], horizontalInset: CGFloat = 0) -> UIStackView {
        let row = UIStackView(arrangedSubviews: letters.map(makeLetterButton))
        row.axis = .horizontal
        row.alignment = .fill
        row.distribution = .fillEqually
        row.spacing = 5
        row.isLayoutMarginsRelativeArrangement = horizontalInset > 0
        row.layoutMargins = UIEdgeInsets(top: 0, left: horizontalInset, bottom: 0, right: horizontalInset)
        return row
    }

    private func makeBottomLetterRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .fill
        row.distribution = .fill
        row.spacing = 5

        configureModifierButton(
            shiftButton,
            title: nil,
            imageName: "shift.fill",
            action: #selector(shiftTapped)
        )
        configureModifierButton(
            deleteButton,
            title: nil,
            imageName: "delete.left",
            action: #selector(deleteTapped)
        )

        let letterRow = makeLetterRow(["z", "x", "c", "v", "b", "n", "m"])
        row.addArrangedSubview(shiftButton)
        row.addArrangedSubview(letterRow)
        row.addArrangedSubview(deleteButton)

        NSLayoutConstraint.activate([
            shiftButton.widthAnchor.constraint(equalToConstant: 45),
            deleteButton.widthAnchor.constraint(equalToConstant: 45)
        ])

        return row
    }

    private func makeCommandRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .fill
        row.distribution = .fill
        row.spacing = 5

        configureModifierButton(
            spaceButton,
            title: "space",
            imageName: nil,
            action: #selector(spaceTapped)
        )
        configureModifierButton(
            returnButton,
            title: "return",
            imageName: nil,
            action: #selector(returnTapped)
        )

        row.addArrangedSubview(spaceButton)
        row.addArrangedSubview(returnButton)

        NSLayoutConstraint.activate([
            returnButton.widthAnchor.constraint(equalToConstant: 76)
        ])

        return row
    }

    private func makeLetterButton(_ letter: String) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityLabel = letter
        button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        styleKeyButton(button, title: letter, imageName: nil, modifier: false)
        letterKeys.append((button: button, letter: letter))
        return button
    }

    private func configureModifierButton(
        _ button: UIButton,
        title: String?,
        imageName: String?,
        action: Selector
    ) {
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        styleKeyButton(button, title: title, imageName: imageName, modifier: true)
    }

    private func styleKeyButton(
        _ button: UIButton,
        title: String?,
        imageName: String?,
        modifier: Bool
    ) {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = imageName.flatMap { UIImage(systemName: $0) }
        config.background.cornerRadius = 6
        config.background.backgroundColor = modifier
            ? KeyboardPalette.modifierKeyBackground(traitCollection)
            : KeyboardPalette.keyBackground(traitCollection)
        config.baseForegroundColor = KeyboardPalette.primaryLabel(traitCollection)
        button.configuration = config
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.layer.cornerRadius = 6
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0 : 0.18
        button.layer.shadowRadius = 0
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    private func updateLetterCaps() {
        for (button, letter) in letterKeys {
            var config = button.configuration
            config?.title = shiftEnabled ? letter.uppercased() : letter.lowercased()
            button.configuration = config
        }

        var shiftConfig = shiftButton.configuration
        shiftConfig?.background.backgroundColor = shiftEnabled
            ? KeyboardPalette.oceanTint.withAlphaComponent(0.22)
            : KeyboardPalette.modifierKeyBackground(traitCollection)
        shiftConfig?.baseForegroundColor = shiftEnabled
            ? KeyboardPalette.oceanTint
            : KeyboardPalette.primaryLabel(traitCollection)
        shiftButton.configuration = shiftConfig
    }

    private func applyKeyboardChrome() {
        // Match Apple's keyboard exactly: clear our own fills so the system's
        // native translucent `.keyboard` material shows through, instead of
        // painting an opaque navy block that reads as a mismatched overlay with
        // a seam above it.
        view.backgroundColor = .clear
        inputView?.backgroundColor = .clear
    }

    private func styleNextKeyboardButton() {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "globe")
        config.background.cornerRadius = 20
        config.background.backgroundColor = KeyboardPalette.modifierKeyBackground(traitCollection)
        config.baseForegroundColor = KeyboardPalette.primaryLabel(traitCollection)
        nextKeyboardButton.configuration = config
        nextKeyboardButton.layer.cornerRadius = 20
        nextKeyboardButton.layer.shadowColor = UIColor.black.cgColor
        nextKeyboardButton.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0 : 0.15
        nextKeyboardButton.layer.shadowRadius = 0
        nextKeyboardButton.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    private func styleReinsertButton() {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "arrow.uturn.backward")
        config.background.cornerRadius = 20
        config.background.backgroundColor = KeyboardPalette.modifierKeyBackground(traitCollection)
        config.baseForegroundColor = KeyboardPalette.oceanTint
        reinsertButton.configuration = config
        reinsertButton.layer.cornerRadius = 20
        reinsertButton.layer.shadowColor = UIColor.black.cgColor
        reinsertButton.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0 : 0.15
        reinsertButton.layer.shadowRadius = 0
        reinsertButton.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    private func updateNextKeyboardButtonVisibility() {
        nextKeyboardButton.isHidden = !needsInputModeSwitchKey
        nextKeyboardButton.isUserInteractionEnabled = needsInputModeSwitchKey
    }

    private func updateReinsertButtonVisibility() {
        let hasTranscript = transcriptRecovery?.load() != nil
        reinsertButton.isHidden = !hasTranscript
        reinsertButton.isUserInteractionEnabled = hasTranscript
    }
}

private enum KeyboardPalette {
    static let oceanTint = UIColor(red: 0.02, green: 0.48, blue: 0.68, alpha: 1)
    static let stopTint = UIColor(red: 0.94, green: 0.38, blue: 0.28, alpha: 1)

    static func keyBackground(_ traits: UITraitCollection) -> UIColor {
        UIColor { incomingTraits in
            let style = incomingTraits.userInterfaceStyle == .unspecified
                ? traits.userInterfaceStyle
                : incomingTraits.userInterfaceStyle
            return style == .dark
                ? UIColor(red: 0.24, green: 0.25, blue: 0.28, alpha: 1)
                : UIColor.white
        }
    }

    static func modifierKeyBackground(_ traits: UITraitCollection) -> UIColor {
        UIColor { incomingTraits in
            let style = incomingTraits.userInterfaceStyle == .unspecified
                ? traits.userInterfaceStyle
                : incomingTraits.userInterfaceStyle
            return style == .dark
                ? UIColor(red: 0.20, green: 0.21, blue: 0.23, alpha: 1)
                : UIColor(red: 0.78, green: 0.80, blue: 0.83, alpha: 1)
        }
    }

    static func primaryLabel(_ traits: UITraitCollection) -> UIColor {
        traits.userInterfaceStyle == .dark ? .white : .black
    }
}
