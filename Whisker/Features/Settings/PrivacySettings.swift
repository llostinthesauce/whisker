import Foundation

final class PrivacySettings: ObservableObject {
    @Published var saveHistory: Bool {
        didSet { UserDefaults.standard.set(saveHistory, forKey: Self.saveHistoryKey) }
    }
    @Published var autoCopyResult: Bool {
        didSet { UserDefaults.standard.set(autoCopyResult, forKey: Self.autoCopyResultKey) }
    }

    init() {
        let saved = UserDefaults.standard.object(forKey: Self.saveHistoryKey) as? Bool
        saveHistory = saved ?? true
        autoCopyResult = UserDefaults.standard.bool(forKey: Self.autoCopyResultKey)
    }

    static let saveHistoryKey = "saveHistory"
    static let autoCopyResultKey = "autoCopyResult"

    static var currentSaveHistory: Bool {
        let saved = UserDefaults.standard.object(forKey: saveHistoryKey) as? Bool
        return saved ?? true
    }

    static var currentAutoCopyResult: Bool {
        UserDefaults.standard.bool(forKey: autoCopyResultKey)
    }
}
