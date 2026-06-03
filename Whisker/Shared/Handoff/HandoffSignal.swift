import Foundation

/// Cross-process "go read now" doorbell built on Darwin notifications.
///
/// Carries no payload by design — the App Group JSON files remain the single
/// source of truth. Every writer posts a signal; the observing process wakes and
/// re-reads the full current file state. Coalesced/dropped signals are harmless
/// because readers never rely on deltas.
enum HandoffSignal {
    enum Channel: String {
        case command = "app.whisker.handoff.command"
        case result = "app.whisker.handoff.result"
    }

    /// Per-channel handlers, isolated to the main actor.
    @MainActor private static var handlers: [String: () -> Void] = [:]

    /// Ring the doorbell for `channel`. Safe to call from any thread.
    static func post(_ channel: Channel) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(channel.rawValue as CFString),
            nil,
            nil,
            true
        )
    }

    /// Run `handler` on the main actor whenever the other process posts `channel`.
    /// Replaces any existing handler for that channel.
    @MainActor
    static func observe(_ channel: Channel, _ handler: @escaping () -> Void) {
        // Remove any prior CF registration first so repeated observe() calls for
        // the same channel never accumulate duplicate callbacks.
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            CFNotificationName(channel.rawValue as CFString),
            nil
        )
        handlers[channel.rawValue] = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, name, _, _ in
                guard let name else { return }
                HandoffSignal.dispatch(name.rawValue as String)
            },
            channel.rawValue as CFString,
            nil,
            .deliverImmediately
        )
    }

    /// Stop observing `channel` and drop its handler.
    @MainActor
    static func stopObserving(_ channel: Channel) {
        handlers[channel.rawValue] = nil
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            CFNotificationName(channel.rawValue as CFString),
            nil
        )
    }

    /// Route a Darwin callback (delivered on an arbitrary thread) to the channel's
    /// handler on the main actor.
    nonisolated private static func dispatch(_ name: String) {
        Task { @MainActor in
            handlers[name]?()
        }
    }
}
