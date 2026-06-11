import AVFoundation
import XCTest
@testable import WhiskerRecorder

final class RecordingSegmenterTests: XCTestCase {
    func testDiscardDeletesCurrentSegmentAndPreventsFutureFinalization() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ))
        let segmenter = RecordingSegmenter(format: format)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
        buffer.frameLength = 1_600
        for frame in 0..<Int(buffer.frameLength) {
            buffer.floatChannelData?[0][frame] = 0.1
        }

        segmenter.ingest(buffer)
        let activeURL = try XCTUnwrap(segmenter.currentSegmentURLForTesting)
        XCTAssertTrue(FileManager.default.fileExists(atPath: activeURL.path))

        segmenter.discardTemporaryAudio()

        XCTAssertFalse(FileManager.default.fileExists(atPath: activeURL.path))
        XCTAssertNil(segmenter.finalize())
    }
}
