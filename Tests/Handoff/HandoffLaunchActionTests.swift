import XCTest
@testable import WhiskerHandoff

final class HandoffLaunchActionTests: XCTestCase {
    func testKeyboardRecordURLRequestsKeyboardSession() {
        XCTAssertEqual(HandoffLaunchAction.resolve(from: HandoffConstants.recordURL), .keyboardSession)
    }

    func testPlainRecordURLStillRequestsOneShotRecording() throws {
        let url = try XCTUnwrap(URL(string: "whisker://record"))

        XCTAssertEqual(HandoffLaunchAction.resolve(from: url), .oneShotRecording)
    }

    func testKeyboardSessionIdleTimeoutCapsMicHotTimeAtFifteenMinutes() {
        // The standby session holds the microphone open for its whole
        // lifetime; this cap bounds battery drain and mic-indicator time.
        XCTAssertEqual(KeyboardSessionDefaults.idleTimeoutSeconds, 15 * 60)
    }
}
