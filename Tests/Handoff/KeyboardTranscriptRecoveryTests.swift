import XCTest
@testable import WhiskerHandoff

final class KeyboardTranscriptRecoveryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "KeyboardTranscriptRecoveryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testLoadsSavedTranscriptWithinMaximumAge() {
        let recovery = KeyboardTranscriptRecovery(defaults: defaults)
        let timestamp = Date(timeIntervalSince1970: 1_774_000_000)

        recovery.save(text: "Recovered words.", timestamp: timestamp)

        XCTAssertEqual(
            recovery.load(now: timestamp.addingTimeInterval(10), maximumAge: 60),
            "Recovered words."
        )
    }

    func testIgnoresBlankTranscript() {
        let recovery = KeyboardTranscriptRecovery(defaults: defaults)
        let timestamp = Date(timeIntervalSince1970: 1_774_000_000)

        recovery.save(text: "   ", timestamp: timestamp)

        XCTAssertNil(recovery.load(now: timestamp, maximumAge: 60))
    }

    func testLoadsNilWhenTranscriptIsStale() {
        let recovery = KeyboardTranscriptRecovery(defaults: defaults)
        let timestamp = Date(timeIntervalSince1970: 1_774_000_000)

        recovery.save(text: "Recovered words.", timestamp: timestamp)

        XCTAssertNil(
            recovery.load(now: timestamp.addingTimeInterval(61), maximumAge: 60)
        )
    }
}
