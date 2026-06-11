import XCTest
@testable import WhiskerRemote

final class SegmentBoundaryDetectorTests: XCTestCase {
    // 0.1s buffers make the math easy: 0.7s silence = 7 silent buffers.
    private let buffer = 0.1

    private func loud(_ d: inout SegmentBoundaryDetector, count: Int) -> [SegmentBoundaryDetector.Decision] {
        (0..<count).map { _ in d.observe(rms: 0.2, durationSeconds: buffer) }
    }

    private func silent(_ d: inout SegmentBoundaryDetector, count: Int) -> [SegmentBoundaryDetector.Decision] {
        (0..<count).map { _ in d.observe(rms: 0.0, durationSeconds: buffer) }
    }

    func testDoesNotCutBeforeMinLengthEvenWithSilence() {
        var d = SegmentBoundaryDetector()
        let decisions = loud(&d, count: 10) + silent(&d, count: 10)
        XCTAssertFalse(decisions.contains(.cut))
    }

    func testCutsOnSilenceAfterMinLength() {
        var d = SegmentBoundaryDetector()
        _ = loud(&d, count: 40)
        let decisions = silent(&d, count: 7)
        XCTAssertEqual(decisions.last, .cut)
    }

    func testForcesCutAtMaxLengthWithoutSilence() {
        var d = SegmentBoundaryDetector()
        let decisions = loud(&d, count: 150)
        XCTAssertTrue(decisions.contains(.cut))
    }

    func testResetClearsCounters() {
        var d = SegmentBoundaryDetector()
        _ = loud(&d, count: 40)
        _ = silent(&d, count: 7)
        d.reset()
        let decisions = silent(&d, count: 7)
        XCTAssertFalse(decisions.contains(.cut))
    }
}
