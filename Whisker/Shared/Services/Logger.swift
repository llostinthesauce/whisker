import Foundation
import os.log

enum WLogger {
    private static let subsystem = "app.whisker"

    static let recorder = Logger(subsystem: subsystem, category: "recorder")
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    static let cleanup = Logger(subsystem: subsystem, category: "cleanup")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let history = Logger(subsystem: subsystem, category: "history")
    static let app = Logger(subsystem: subsystem, category: "app")
}
