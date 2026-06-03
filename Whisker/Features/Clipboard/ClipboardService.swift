import UIKit

@MainActor
final class ClipboardService {
    func copy(_ text: String) {
        UIPasteboard.general.string = text
        WLogger.app.info("Copied \(text.count) characters to clipboard")
    }
}
