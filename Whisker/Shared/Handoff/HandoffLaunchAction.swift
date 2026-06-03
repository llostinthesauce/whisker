import Foundation

enum HandoffLaunchAction: Equatable {
    case keyboardSession
    case oneShotRecording

    static func resolve(from url: URL) -> HandoffLaunchAction? {
        guard url.scheme == HandoffConstants.urlScheme else { return nil }

        switch url.host {
        case "record":
            return isKeyboardSource(url) ? .keyboardSession : .oneShotRecording
        case "keyboard-session":
            return .keyboardSession
        default:
            return nil
        }
    }

    private static func isKeyboardSource(_ url: URL) -> Bool {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.contains { item in
            item.name == "source" && item.value == "keyboard"
        } == true
    }
}
