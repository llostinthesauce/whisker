import Combine
import Foundation
#if canImport(Security)
import Security
#endif

struct RemoteMacDefaultEndpoints: Equatable, Sendable {
    let localBaseURLString: String
    let fallbackBaseURLString: String

    static let empty = RemoteMacDefaultEndpoints(
        localBaseURLString: "",
        fallbackBaseURLString: ""
    )

    static func appBundle(_ bundle: Bundle = .main) -> RemoteMacDefaultEndpoints {
        RemoteMacDefaultEndpoints(
            localBaseURLString: bundle.object(forInfoDictionaryKey: "WhiskerDefaultLocalServerURL") as? String ?? "",
            fallbackBaseURLString: bundle.object(forInfoDictionaryKey: "WhiskerDefaultFallbackServerURL") as? String ?? ""
        )
    }
}

final class RemoteMacSettings: ObservableObject {
    @Published var baseURLString: String {
        didSet { userDefaults.set(baseURLString, forKey: Self.baseURLKey) }
    }

    @Published var fallbackBaseURLString: String {
        didSet { userDefaults.set(fallbackBaseURLString, forKey: Self.fallbackBaseURLKey) }
    }

    @Published var bearerToken: String {
        didSet { tokenStore.write(bearerToken) }
    }

    @Published var timeoutSeconds: Double {
        didSet { userDefaults.set(timeoutSeconds, forKey: Self.timeoutSecondsKey) }
    }

    @Published var selectedModelID: String {
        didSet { userDefaults.set(selectedModelID, forKey: Self.selectedModelIDKey) }
    }

    private let userDefaults: UserDefaults
    private let tokenStore: RemoteMacTokenStoring

    init(
        userDefaults: UserDefaults = .standard,
        tokenStore: RemoteMacTokenStoring = RemoteMacKeychainTokenStore(),
        defaultEndpoints: RemoteMacDefaultEndpoints = .appBundle()
    ) {
        self.userDefaults = userDefaults
        self.tokenStore = tokenStore
        Self.seedDefaultEndpointsIfNeeded(in: userDefaults, defaultEndpoints: defaultEndpoints)
        baseURLString = userDefaults.string(forKey: Self.baseURLKey) ?? ""
        fallbackBaseURLString = userDefaults.string(forKey: Self.fallbackBaseURLKey) ?? ""
        bearerToken = tokenStore.read() ?? ""
        let savedTimeout = userDefaults.double(forKey: Self.timeoutSecondsKey)
        timeoutSeconds = Self.normalizedTimeout(savedTimeout)
        selectedModelID = userDefaults.string(forKey: Self.selectedModelIDKey) ?? "balanced"
    }

    static let baseURLKey = "remoteMacBaseURL"
    static let fallbackBaseURLKey = "remoteMacFallbackBaseURL"
    static let endpointSeedVersionKey = "remoteMacEndpointSeedVersion"
    static let timeoutSecondsKey = "remoteMacTimeoutSeconds"
    static let selectedModelIDKey = "remoteMacSelectedModelID"
    private static let endpointSeedVersion = 1

    var configuration: RemoteMacClientConfiguration? {
        Self.configuration(
            baseURLString: baseURLString,
            fallbackBaseURLString: fallbackBaseURLString,
            bearerToken: bearerToken,
            timeoutSeconds: timeoutSeconds,
            modelID: selectedModelID
        )
    }

    static var currentConfiguration: RemoteMacClientConfiguration? {
        let defaults = UserDefaults.standard
        let tokenStore = RemoteMacKeychainTokenStore()
        seedDefaultEndpointsIfNeeded(in: defaults, defaultEndpoints: .appBundle())
        return configuration(
            baseURLString: defaults.string(forKey: baseURLKey) ?? "",
            fallbackBaseURLString: defaults.string(forKey: fallbackBaseURLKey) ?? "",
            bearerToken: tokenStore.read() ?? "",
            timeoutSeconds: {
                let saved = defaults.double(forKey: timeoutSecondsKey)
                return normalizedTimeout(saved)
            }(),
            modelID: defaults.string(forKey: selectedModelIDKey) ?? "balanced"
        )
    }

    private static func seedDefaultEndpointsIfNeeded(
        in defaults: UserDefaults,
        defaultEndpoints: RemoteMacDefaultEndpoints
    ) {
        guard defaults.integer(forKey: endpointSeedVersionKey) < endpointSeedVersion else {
            return
        }

        let existingLocal = defaults.string(forKey: baseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let existingFallback = defaults.string(forKey: fallbackBaseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let defaultLocal = defaultEndpoints.localBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultFallback = defaultEndpoints.fallbackBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        if existingLocal.isEmpty, !defaultLocal.isEmpty {
            defaults.set(defaultLocal, forKey: baseURLKey)
        }
        if existingFallback.isEmpty, !defaultFallback.isEmpty {
            defaults.set(defaultFallback, forKey: fallbackBaseURLKey)
        }
        defaults.set(endpointSeedVersion, forKey: endpointSeedVersionKey)
    }

    private static func configuration(
        baseURLString: String,
        fallbackBaseURLString: String,
        bearerToken: String,
        timeoutSeconds: Double,
        modelID: String
    ) -> RemoteMacClientConfiguration? {
        let trimmedToken = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            return nil
        }

        let trimmedLocalURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFallbackURL = fallbackBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let localEndpoint = endpoint(from: trimmedLocalURL, label: "Local")
        let fallbackEndpoint = endpoint(from: trimmedFallbackURL, label: "Tailscale")

        guard (trimmedLocalURL.isEmpty || localEndpoint != nil),
              (trimmedFallbackURL.isEmpty || fallbackEndpoint != nil) else {
            return nil
        }

        var endpoints = [RemoteMacEndpoint]()
        if let localEndpoint {
            endpoints.append(localEndpoint)
        }
        if let fallbackEndpoint, !endpoints.contains(where: { $0.baseURL == fallbackEndpoint.baseURL }) {
            endpoints.append(fallbackEndpoint)
        }

        guard !endpoints.isEmpty else {
            return nil
        }

        return RemoteMacClientConfiguration(
            endpoints: endpoints,
            bearerToken: trimmedToken,
            timeoutSeconds: timeoutSeconds,
            modelID: modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func endpoint(from urlString: String, label: String) -> RemoteMacEndpoint? {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }
        return RemoteMacEndpoint(label: label, baseURL: url)
    }

    static func normalizedTimeout(_ seconds: Double) -> Double {
        let allowed = [60.0, 300.0]
        return allowed.contains(seconds) ? seconds : 300
    }
}

protocol RemoteMacTokenStoring {
    func read() -> String?
    func write(_ token: String)
}

struct RemoteMacKeychainTokenStore: RemoteMacTokenStoring {
    private let service = "app.whisker.remote-mac"
    private let account = "bearer-token"

    func read() -> String? {
#if canImport(Security)
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
#else
        return UserDefaults.standard.string(forKey: "remoteMacBearerToken")
#endif
    }

    func write(_ token: String) {
#if canImport(Security)
        SecItemDelete(baseQuery() as CFDictionary)
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return
        }

        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
#else
        UserDefaults.standard.set(token, forKey: "remoteMacBearerToken")
#endif
    }

#if canImport(Security)
    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
#endif
}
