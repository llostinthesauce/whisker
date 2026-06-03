import Foundation

public struct RemoteModelProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let engine: String
    public let model: String
    public let speed: String
    public let description: String

    public init(
        id: String,
        label: String,
        engine: String,
        model: String,
        speed: String,
        description: String
    ) {
        self.id = id
        self.label = label
        self.engine = engine
        self.model = model
        self.speed = speed
        self.description = description
    }

    public static let defaults: [RemoteModelProfile] = [
        RemoteModelProfile(
            id: "fast",
            label: "Fast",
            engine: "parakeet_mlx",
            model: "mlx-community/parakeet-tdt_ctc-110m",
            speed: "fast",
            description: "Small 110M Parakeet CTC model for short dictation."
        ),
        RemoteModelProfile(
            id: "balanced",
            label: "Balanced",
            engine: "parakeet_mlx",
            model: "mlx-community/parakeet-tdt-0.6b-v3",
            speed: "medium",
            description: "Current default Parakeet TDT 0.6B v3 model."
        )
    ]
}

public struct RemoteHealthResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let server: String
    public let version: String
    public let engine: String
    public let model: String
    public let defaultModelID: String?
    public let models: [RemoteModelProfile]
    public let cleanup: [String]
    public let maxDurationSeconds: Double

    public init(
        ok: Bool,
        server: String,
        version: String,
        engine: String,
        model: String,
        defaultModelID: String? = nil,
        models: [RemoteModelProfile] = [],
        cleanup: [String],
        maxDurationSeconds: Double
    ) {
        self.ok = ok
        self.server = server
        self.version = version
        self.engine = engine
        self.model = model
        self.defaultModelID = defaultModelID
        self.models = models
        self.cleanup = cleanup
        self.maxDurationSeconds = maxDurationSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        server = try container.decode(String.self, forKey: .server)
        version = try container.decode(String.self, forKey: .version)
        engine = try container.decode(String.self, forKey: .engine)
        model = try container.decode(String.self, forKey: .model)
        defaultModelID = try container.decodeIfPresent(String.self, forKey: .defaultModelID)
        models = try container.decodeIfPresent([RemoteModelProfile].self, forKey: .models) ?? []
        cleanup = try container.decode([String].self, forKey: .cleanup)
        maxDurationSeconds = try container.decode(Double.self, forKey: .maxDurationSeconds)
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case server
        case version
        case engine
        case model
        case defaultModelID = "default_model_id"
        case models
        case cleanup
        case maxDurationSeconds = "max_duration_seconds"
    }
}

public struct RemoteTranscriptSegment: Codable, Equatable, Sendable {
    public let start: Double?
    public let end: Double?
    public let text: String?

    public init(start: Double? = nil, end: Double? = nil, text: String? = nil) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct RemoteTranscriptionResponse: Codable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let cleanedText: String?
    public let durationSeconds: Double
    public let engine: String
    public let model: String
    public let modelID: String?
    public let processingSeconds: Double?
    public let segments: [RemoteTranscriptSegment]
    public let warnings: [String]

    public init(
        id: String,
        text: String,
        cleanedText: String?,
        durationSeconds: Double,
        engine: String,
        model: String,
        modelID: String? = nil,
        processingSeconds: Double?,
        segments: [RemoteTranscriptSegment],
        warnings: [String]
    ) {
        self.id = id
        self.text = text
        self.cleanedText = cleanedText
        self.durationSeconds = durationSeconds
        self.engine = engine
        self.model = model
        self.modelID = modelID
        self.processingSeconds = processingSeconds
        self.segments = segments
        self.warnings = warnings
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case cleanedText = "cleaned_text"
        case durationSeconds = "duration_seconds"
        case engine
        case model
        case modelID = "model_id"
        case processingSeconds = "processing_seconds"
        case segments
        case warnings
    }
}
