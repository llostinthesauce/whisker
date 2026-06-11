import XCTest
@testable import WhiskerRemote

final class RemoteMacModelsTests: XCTestCase {
    func testHealthResponseDecodesSnakeCaseServerContract() throws {
        let json = """
        {
          "ok": true,
          "server": "whisker-server",
          "version": "0.1.0",
          "engine": "sherpa-onnx",
          "model": "parakeet-110m-int8",
          "cleanup": ["raw", "light", "message"],
          "max_duration_seconds": 300
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RemoteHealthResponse.self, from: json)

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.server, "whisker-server")
        XCTAssertEqual(response.engine, "sherpa-onnx")
        XCTAssertEqual(response.model, "parakeet-110m-int8")
        XCTAssertNil(response.defaultModelID)
        XCTAssertEqual(response.models, [])
        XCTAssertEqual(response.cleanup, ["raw", "light", "message"])
        XCTAssertEqual(response.maxDurationSeconds, 300)
    }

    func testHealthResponseDecodesModelProfiles() throws {
        let json = """
        {
          "ok": true,
          "server": "demo-whisker",
          "version": "0.1.0",
          "engine": "parakeet-mlx",
          "model": "mlx-community/parakeet-tdt-0.6b-v3",
          "default_model_id": "balanced",
          "models": [
            {
              "id": "fast",
              "label": "Fast",
              "engine": "parakeet_mlx",
              "model": "mlx-community/parakeet-tdt_ctc-110m",
              "speed": "fast",
              "description": "Small 110M Parakeet CTC model for short dictation."
            },
            {
              "id": "balanced",
              "label": "Balanced",
              "engine": "parakeet_mlx",
              "model": "mlx-community/parakeet-tdt-0.6b-v3",
              "speed": "medium",
              "description": "Current default Parakeet TDT 0.6B v3 model."
            }
          ],
          "cleanup": ["raw", "light", "message", "email", "notes", "bullets"],
          "max_duration_seconds": 300
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RemoteHealthResponse.self, from: json)

        XCTAssertEqual(response.defaultModelID, "balanced")
        XCTAssertEqual(response.models.map(\.id), ["fast", "balanced"])
        XCTAssertEqual(response.models[0].model, "mlx-community/parakeet-tdt_ctc-110m")
    }

    func testTranscriptionResponseDecodesSnakeCaseServerContract() throws {
        let json = """
        {
          "id": "d8b1744d-4c19-4c8f-9f53-6a3d9d3fd7f2",
          "text": "raw transcript",
          "cleaned_text": "cleaned transcript",
          "duration_seconds": 12.4,
          "engine": "sherpa-onnx",
          "model": "parakeet-110m-int8",
          "model_id": "fast",
          "processing_seconds": 1.7,
          "segments": [],
          "warnings": ["low confidence"]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RemoteTranscriptionResponse.self, from: json)

        XCTAssertEqual(response.id, "d8b1744d-4c19-4c8f-9f53-6a3d9d3fd7f2")
        XCTAssertEqual(response.text, "raw transcript")
        XCTAssertEqual(response.cleanedText, "cleaned transcript")
        XCTAssertEqual(response.durationSeconds, 12.4)
        XCTAssertEqual(response.engine, "sherpa-onnx")
        XCTAssertEqual(response.model, "parakeet-110m-int8")
        XCTAssertEqual(response.modelID, "fast")
        XCTAssertEqual(response.processingSeconds, 1.7)
        XCTAssertEqual(response.warnings, ["low confidence"])
    }
}
