import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if SWIFT_PACKAGE
import WhiskerCleanup
#endif

struct RemoteMacEndpoint: Equatable, Sendable {
    let label: String
    let baseURL: URL
}

struct RemoteMacClientConfiguration: Equatable, Sendable {
    let endpoints: [RemoteMacEndpoint]
    let bearerToken: String
    let timeoutSeconds: TimeInterval
    let modelID: String?

    var baseURL: URL {
        endpoints[0].baseURL
    }

    init(
        baseURL: URL,
        fallbackBaseURL: URL? = nil,
        bearerToken: String,
        timeoutSeconds: TimeInterval = 60,
        modelID: String? = nil
    ) {
        var endpoints = [RemoteMacEndpoint(label: "Local", baseURL: baseURL)]
        if let fallbackBaseURL, fallbackBaseURL != baseURL {
            endpoints.append(RemoteMacEndpoint(label: "Tailscale", baseURL: fallbackBaseURL))
        }
        self.init(
            endpoints: endpoints,
            bearerToken: bearerToken,
            timeoutSeconds: timeoutSeconds,
            modelID: modelID
        )
    }

    init(
        endpoints: [RemoteMacEndpoint],
        bearerToken: String,
        timeoutSeconds: TimeInterval = 60,
        modelID: String? = nil
    ) {
        precondition(!endpoints.isEmpty, "Remote Mac configuration requires at least one endpoint.")
        self.endpoints = endpoints
        self.bearerToken = bearerToken
        self.timeoutSeconds = timeoutSeconds
        self.modelID = modelID
    }
}

enum RemoteMacError: Error, LocalizedError, Equatable {
    case missingToken
    case uploadFileUnreadable
    case invalidResponse
    case unauthorized
    case timeout
    case fileTooLarge
    case emptyTranscript
    case serverUnavailable(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Server token is missing."
        case .uploadFileUnreadable:
            return "Recording file could not be read for upload."
        case .invalidResponse:
            return "Server returned an invalid response."
        case .unauthorized:
            return "Server rejected the bearer token."
        case .timeout:
            return "Server request timed out."
        case .fileTooLarge:
            return "Recording is too large for the server."
        case .emptyTranscript:
            return "No speech was detected in the recording."
        case .serverUnavailable(let statusCode):
            return "Server request failed with HTTP \(statusCode)."
        }
    }
}

protocol RemoteMacClientProtocol: AnyObject, Sendable {
    func health() async throws -> RemoteHealthResponse
    func transcribe(audioURL: URL, cleanupMode: CleanupMode, returnCleaned: Bool) async throws -> RemoteTranscriptionResponse
}

final class RemoteMacClient: RemoteMacClientProtocol, @unchecked Sendable {
    private let configuration: RemoteMacClientConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let fallbackProbeTimeoutSeconds: TimeInterval = 3

    init(configuration: RemoteMacClientConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func health() async throws -> RemoteHealthResponse {
        try await sendOverEndpoints(
            as: RemoteHealthResponse.self,
            quickTimeoutForFallbackCandidates: true
        ) { endpoint, timeoutSeconds in
            var request = try makeRequest(endpoint: endpoint, path: "v1/health", timeoutSeconds: timeoutSeconds)
            request.httpMethod = "GET"
            return request
        }
    }

    func transcribe(audioURL: URL, cleanupMode: CleanupMode, returnCleaned: Bool) async throws -> RemoteTranscriptionResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        // Recordings can run to tens of megabytes; compose the multipart body
        // on disk and let URLSession stream it from the file instead of
        // holding the audio (and a second copy in the body) in memory.
        let bodyFileURL = try makeMultipartBodyFile(
            boundary: boundary,
            audioURL: audioURL,
            cleanupMode: cleanupMode,
            returnCleaned: returnCleaned
        )
        defer { try? FileManager.default.removeItem(at: bodyFileURL) }

        return try await sendOverEndpoints(
            as: RemoteTranscriptionResponse.self,
            preflightFallbackCandidates: true,
            uploadingBodyFile: bodyFileURL
        ) { endpoint, timeoutSeconds in
            var request = try makeRequest(endpoint: endpoint, path: "v1/transcribe", timeoutSeconds: timeoutSeconds)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            return request
        }
    }

    private func makeRequest(
        endpoint: RemoteMacEndpoint,
        path: String,
        timeoutSeconds: TimeInterval? = nil
    ) throws -> URLRequest {
        let token = configuration.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw RemoteMacError.missingToken
        }

        let url = endpoint.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url, timeoutInterval: timeoutSeconds ?? configuration.timeoutSeconds)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func sendOverEndpoints<T: Decodable>(
        as type: T.Type,
        quickTimeoutForFallbackCandidates: Bool = false,
        preflightFallbackCandidates: Bool = false,
        uploadingBodyFile bodyFileURL: URL? = nil,
        requestFactory: (RemoteMacEndpoint, TimeInterval?) throws -> URLRequest
    ) async throws -> T {
        var lastError: Error?
        for (index, endpoint) in configuration.endpoints.enumerated() {
            let hasFallback = index < configuration.endpoints.index(before: configuration.endpoints.endIndex)
            if hasFallback && preflightFallbackCandidates {
                do {
                    try await preflight(endpoint: endpoint)
                } catch {
                    lastError = error
                    guard shouldTryNextEndpoint(after: error) else {
                        throw error
                    }
                    continue
                }
            }

            do {
                let timeoutSeconds = hasFallback && quickTimeoutForFallbackCandidates ? fallbackProbeTimeoutSeconds : nil
                return try await send(
                    try requestFactory(endpoint, timeoutSeconds),
                    uploadingBodyFile: bodyFileURL,
                    as: type
                )
            } catch {
                lastError = error
                guard shouldTryNextEndpoint(after: error) else {
                    throw error
                }
            }
        }

        throw lastError ?? RemoteMacError.invalidResponse
    }

    private func preflight(endpoint: RemoteMacEndpoint) async throws {
        var request = try makeRequest(
            endpoint: endpoint,
            path: "v1/health",
            timeoutSeconds: fallbackProbeTimeoutSeconds
        )
        request.httpMethod = "GET"
        _ = try await send(request, as: RemoteHealthResponse.self)
    }

    private func send<T: Decodable>(
        _ request: URLRequest,
        uploadingBodyFile bodyFileURL: URL? = nil,
        as type: T.Type
    ) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            if let bodyFileURL {
                (data, response) = try await session.upload(for: request, fromFile: bodyFileURL)
            } else {
                (data, response) = try await session.data(for: request)
            }
        } catch let error as URLError where error.code == .timedOut {
            throw RemoteMacError.timeout
        } catch {
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteMacError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw RemoteMacError.invalidResponse
            }
        case 401, 403:
            throw RemoteMacError.unauthorized
        case 408:
            throw RemoteMacError.timeout
        case 413:
            throw RemoteMacError.fileTooLarge
        case 422:
            // The server transcribed the audio and found no speech. The server
            // is healthy — retrying the same audio on the fallback endpoint
            // would just re-upload it for the same answer.
            throw RemoteMacError.emptyTranscript
        default:
            throw RemoteMacError.serverUnavailable(statusCode: httpResponse.statusCode)
        }
    }

    private func shouldTryNextEndpoint(after error: Error) -> Bool {
        if error is URLError {
            return true
        }

        guard let remoteError = error as? RemoteMacError else {
            return false
        }

        switch remoteError {
        case .timeout, .invalidResponse, .serverUnavailable:
            return true
        case .missingToken, .uploadFileUnreadable, .unauthorized, .fileTooLarge, .emptyTranscript:
            return false
        }
    }

    /// Writes the multipart request body to a temporary file, copying the
    /// audio across in 1 MiB chunks. The caller owns deleting the returned file.
    private func makeMultipartBodyFile(
        boundary: String,
        audioURL: URL,
        cleanupMode: CleanupMode,
        returnCleaned: Bool
    ) throws -> URL {
        var prefix = Data()
        prefix.appendFormField(name: "cleanup_mode", value: cleanupMode.rawValue, boundary: boundary)
        if let modelID = configuration.modelID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !modelID.isEmpty {
            prefix.appendFormField(name: "model_id", value: modelID, boundary: boundary)
        }
        prefix.appendFormField(name: "return_cleaned", value: returnCleaned ? "true" : "false", boundary: boundary)
        prefix.append("--\(boundary)\r\n")
        prefix.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n")
        prefix.append("Content-Type: application/octet-stream\r\n\r\n")

        let bodyFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisker-upload-\(UUID().uuidString).multipart")
        do {
            guard let reader = FileHandle(forReadingAtPath: audioURL.path) else {
                throw RemoteMacError.uploadFileUnreadable
            }
            defer { try? reader.close() }

            FileManager.default.createFile(atPath: bodyFileURL.path, contents: nil)
            let writer = try FileHandle(forWritingTo: bodyFileURL)
            defer { try? writer.close() }

            try writer.write(contentsOf: prefix)
            while let chunk = try reader.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                try writer.write(contentsOf: chunk)
            }
            try writer.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        } catch {
            try? FileManager.default.removeItem(at: bodyFileURL)
            throw RemoteMacError.uploadFileUnreadable
        }
        return bodyFileURL
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendFormField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }
}
