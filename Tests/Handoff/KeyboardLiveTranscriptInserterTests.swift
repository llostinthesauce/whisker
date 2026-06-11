import XCTest
@testable import WhiskerHandoff

final class KeyboardLiveTranscriptInserterTests: XCTestCase {
    func testLiveUpdatesInsertOnlyDelta() {
        var inserter = KeyboardLiveTranscriptInserter()

        let first = inserter.updateLiveText("hello")
        let second = inserter.updateLiveText("hello world")

        XCTAssertEqual(first, KeyboardLiveTranscriptEdit(deleteCharacterCount: 0, insertText: "hello"))
        XCTAssertEqual(second, KeyboardLiveTranscriptEdit(deleteCharacterCount: 0, insertText: " world"))
    }

    func testRevisedLiveTextReplacesPriorProvisionalText() {
        var inserter = KeyboardLiveTranscriptInserter()

        _ = inserter.updateLiveText("yellow")
        let revision = inserter.updateLiveText("hello world")

        XCTAssertEqual(revision, KeyboardLiveTranscriptEdit(deleteCharacterCount: 6, insertText: "hello world"))
    }

    func testFinalTextReplacesProvisionalTextAndResets() {
        var inserter = KeyboardLiveTranscriptInserter()

        _ = inserter.updateLiveText("hello raw")
        let final = inserter.finalize(with: "Hello, raw.")
        let next = inserter.updateLiveText("new")

        XCTAssertEqual(final, KeyboardLiveTranscriptEdit(deleteCharacterCount: 9, insertText: "Hello, raw."))
        XCTAssertEqual(next, KeyboardLiveTranscriptEdit(deleteCharacterCount: 0, insertText: "new"))
    }
}
