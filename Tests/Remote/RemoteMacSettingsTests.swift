import XCTest
@testable import WhiskerRemote

final class RemoteMacSettingsTests: XCTestCase {
    func testConfigurationRejectsRelativeServerURL() {
        let settings = makeSettings(baseURL: "whisker-server", token: "secret")

        XCTAssertNil(settings.configuration)
    }

    func testConfigurationRejectsUnsupportedServerScheme() {
        let settings = makeSettings(baseURL: "ftp://whisker-server:8787", token: "secret")

        XCTAssertNil(settings.configuration)
    }

    func testConfigurationAcceptsHTTPServerURL() throws {
        let settings = makeSettings(baseURL: "http://whisker-server:8787", token: "secret")

        let configuration = try XCTUnwrap(settings.configuration)
        XCTAssertEqual(configuration.baseURL.absoluteString, "http://whisker-server:8787")
        XCTAssertEqual(configuration.endpoints.map(\.baseURL.absoluteString), ["http://whisker-server:8787"])
        XCTAssertEqual(configuration.bearerToken, "secret")
    }

    func testConfigurationOrdersLocalBeforeTailscaleFallback() throws {
        let settings = makeSettings(
            baseURL: "http://lan-whisker.test:8787",
            fallbackBaseURL: "https://whisker-tailnet.example.test",
            token: "secret"
        )

        let configuration = try XCTUnwrap(settings.configuration)

        XCTAssertEqual(configuration.endpoints.map(\.label), ["Local", "Tailscale"])
        XCTAssertEqual(configuration.endpoints.map(\.baseURL.absoluteString), [
            "http://lan-whisker.test:8787",
            "https://whisker-tailnet.example.test"
        ])
    }

    func testConfigurationAllowsTailscaleOnlyWhenLocalIsEmpty() throws {
        let settings = makeSettings(
            baseURL: "",
            fallbackBaseURL: "https://whisker-tailnet.example.test",
            token: "secret"
        )

        let configuration = try XCTUnwrap(settings.configuration)

        XCTAssertEqual(configuration.baseURL.absoluteString, "https://whisker-tailnet.example.test")
        XCTAssertEqual(configuration.endpoints.map(\.label), ["Tailscale"])
    }

    func testConfigurationCapsSavedTimeoutAtFiveMinutes() throws {
        let settings = makeSettings(
            baseURL: "http://whisker-server:8787",
            token: "secret",
            savedTimeout: 3600
        )

        let configuration = try XCTUnwrap(settings.configuration)

        XCTAssertEqual(settings.timeoutSeconds, 300)
        XCTAssertEqual(configuration.timeoutSeconds, 300)
    }

    func testConfigurationDoesNotSeedPersonalDefaultsInPublicBuild() {
        let suiteName = "RemoteMacSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = RemoteMacSettings(
            userDefaults: defaults,
            tokenStore: StubRemoteMacTokenStore(token: "secret")
        )

        XCTAssertEqual(settings.baseURLString, "")
        XCTAssertEqual(settings.fallbackBaseURLString, "")
        XCTAssertNil(settings.configuration)
    }

    func testConfigurationSeedsBuildProvidedDefaultsWhenFallbackHasNeverBeenConfigured() throws {
        let suiteName = "RemoteMacSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let defaultEndpoints = RemoteMacDefaultEndpoints(
            localBaseURLString: "http://lan-whisker.test:8787",
            fallbackBaseURLString: "https://whisker-tailnet.example.test"
        )
        let settings = RemoteMacSettings(
            userDefaults: defaults,
            tokenStore: StubRemoteMacTokenStore(token: "secret"),
            defaultEndpoints: defaultEndpoints
        )

        let configuration = try XCTUnwrap(settings.configuration)

        XCTAssertEqual(settings.baseURLString, defaultEndpoints.localBaseURLString)
        XCTAssertEqual(settings.fallbackBaseURLString, defaultEndpoints.fallbackBaseURLString)
        XCTAssertEqual(configuration.endpoints.map(\.baseURL.absoluteString), [
            defaultEndpoints.localBaseURLString,
            defaultEndpoints.fallbackBaseURLString
        ])
    }

    private func makeSettings(
        baseURL: String,
        fallbackBaseURL: String = "",
        token: String,
        savedTimeout: Double? = nil
    ) -> RemoteMacSettings {
        let suiteName = "RemoteMacSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(baseURL, forKey: RemoteMacSettings.baseURLKey)
        defaults.set(fallbackBaseURL, forKey: RemoteMacSettings.fallbackBaseURLKey)
        defaults.set(1, forKey: RemoteMacSettings.endpointSeedVersionKey)
        if let savedTimeout {
            defaults.set(savedTimeout, forKey: RemoteMacSettings.timeoutSecondsKey)
        }
        return RemoteMacSettings(
            userDefaults: defaults,
            tokenStore: StubRemoteMacTokenStore(token: token)
        )
    }
}

private final class StubRemoteMacTokenStore: RemoteMacTokenStoring {
    private var token: String?

    init(token: String?) {
        self.token = token
    }

    func read() -> String? {
        token
    }

    func write(_ token: String) {
        self.token = token
    }
}
