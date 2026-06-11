import XCTest
@testable import WhiskerHandoff

@MainActor
final class HandoffSignalTests: XCTestCase {
    override func tearDown() {
        HandoffSignal.stopObserving(.command)
        HandoffSignal.stopObserving(.result)
        super.tearDown()
    }

    func testChannelNamesAreStable() {
        XCTAssertEqual(HandoffSignal.Channel.command.rawValue, "app.whisker.handoff.command")
        XCTAssertEqual(HandoffSignal.Channel.result.rawValue, "app.whisker.handoff.result")
    }

    func testObserverFiresWhenChannelIsPosted() {
        let fired = expectation(description: "result handler runs after post")
        HandoffSignal.observe(.result) { fired.fulfill() }

        HandoffSignal.post(.result)

        wait(for: [fired], timeout: 2.0)
    }

    func testStopObservingPreventsHandler() {
        let fired = expectation(description: "command handler must not run after removal")
        fired.isInverted = true
        HandoffSignal.observe(.command) { fired.fulfill() }

        HandoffSignal.stopObserving(.command)
        HandoffSignal.post(.command)

        wait(for: [fired], timeout: 1.0)
    }

    func testObserverIsChannelScoped() {
        let wrongChannel = expectation(description: "command handler must not run for a result post")
        wrongChannel.isInverted = true
        HandoffSignal.observe(.command) { wrongChannel.fulfill() }

        HandoffSignal.post(.result)

        wait(for: [wrongChannel], timeout: 1.0)
    }

    func testReobservingDoesNotStackHandlers() {
        var fireCount = 0
        let fired = expectation(description: "handler runs exactly once after re-observe")
        HandoffSignal.observe(.result) { fireCount += 1 }
        HandoffSignal.observe(.result) {
            fireCount += 1
            fired.fulfill()
        }

        HandoffSignal.post(.result)

        wait(for: [fired], timeout: 2.0)
        // Give any stacked duplicate callback a chance to also fire before asserting.
        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settle.fulfill() }
        wait(for: [settle], timeout: 1.0)
        XCTAssertEqual(fireCount, 1)
    }
}
