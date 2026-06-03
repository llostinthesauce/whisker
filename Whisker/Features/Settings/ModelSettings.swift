import Foundation

final class ModelSettings: ObservableObject {
    @Published var defaultCleanupMode: CleanupMode {
        didSet {
            if !defaultCleanupMode.isImplemented {
                defaultCleanupMode = .raw
                return
            }
            UserDefaults.standard.set(defaultCleanupMode.rawValue, forKey: Self.defaultCleanupModeKey)
        }
    }

    init() {
        defaultCleanupMode = Self.currentDefaultCleanupMode
    }

    static let defaultCleanupModeKey = "defaultCleanupMode"

    static var currentDefaultCleanupMode: CleanupMode {
        let raw = UserDefaults.standard.string(forKey: defaultCleanupModeKey) ?? ""
        let mode = CleanupMode(rawValue: raw) ?? .raw
        return mode.isImplemented ? mode : .raw
    }
}
