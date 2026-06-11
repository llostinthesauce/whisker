import XCTest
@testable import WhiskerCleanup

/// RuleBasedCleaner is a port of server/cleanup/rules.py. These cases mirror
/// server/tests/test_cleanup.py so on-device cleanup of streaming joins stays
/// byte-identical to the server's batch cleanup. If a case here changes, the
/// server rules and tests must change with it.
final class RuleBasedCleanerTests: XCTestCase {
    private let cleaner = RuleBasedCleaner()

    func testRawModeReturnsInputUnchanged() async throws {
        let input = "  keep   spacing \n\n\n end "

        let output = try await cleaner.clean(input, mode: .raw)

        XCTAssertEqual(output, input)
    }

    func testLightModeNormalizesSpacesWithoutCollapsingParagraphs() async throws {
        // Mirrors test_normalizes_spaces_without_collapsing_paragraphs.
        let input = " hello   there\n\n\nsecond\tline "

        let output = try await cleaner.clean(input, mode: .light)

        XCTAssertEqual(output, "hello there\n\nsecond line")
    }

    func testLightModePreservesAlreadyCapitalizedText() async throws {
        let output = try await cleaner.clean("Already   fine.", mode: .light)

        XCTAssertEqual(output, "Already fine.")
    }

    func testMessageModeCapitalizesWithoutAppendingPunctuation() async throws {
        // Mirrors test_message_capitalizes_first_letter_after_light_cleanup:
        // the server does not append a terminal period, so neither do we.
        let output = try await cleaner.clean(" hello   there ", mode: .message)

        XCTAssertEqual(output, "Hello there")
    }

    func testEmailModeMatchesMessageMode() async throws {
        let message = try await cleaner.clean(" hello   there ", mode: .message)
        let email = try await cleaner.clean(" hello   there ", mode: .email)

        XCTAssertEqual(email, message)
    }

    func testNotesModeSplitsSentencesOntoLines() async throws {
        let output = try await cleaner.clean("First thing. second thing third thing?", mode: .notes)

        XCTAssertEqual(output, "First thing.\nSecond thing third thing?")
    }

    func testBulletsModeSplitsSentences() async throws {
        // Mirrors test_bullets_split_sentences.
        let output = try await cleaner.clean("first thing. second thing? final thing!", mode: .bullets)

        XCTAssertEqual(output, "- First thing.\n- Second thing?\n- Final thing!")
    }
}
