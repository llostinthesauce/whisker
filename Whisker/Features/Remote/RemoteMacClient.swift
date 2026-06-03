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
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            throw RemoteMacError.uploadFileUnreadable
        }

        let body = makeMultipartBody(
            boundary: boundary,
            audioData: audioData,
            filename: audioURL.lastPathComponent,
            cleanupMode: cleanupMode,
            returnCleaned: returnCleaned
        )

        return try await sendOverEndpoints(
            as: RemoteTranscriptionResponse.self,
            preflightFallbackCandidates: true
        ) { endpoint, timeoutSeconds in
            var request = try makeRequest(endpoint: endpoint, path: "v1/transcribe", timeoutSeconds: timeoutSeconds)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
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
                return try await send(try requestFactory(endpoint, timeoutSeconds), as: type)
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

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
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
        case .missingToken, .uploadFileUnreadable, .unauthorized, .fileTooLarge:
            return false
        }
    }

    private func makeMultipartBody(
        boundary: String,
        audioData: Data,
        filename: String,
        cleanupMode: CleanupMode,
        returnCleaned: Bool
    ) -> Data {
        var body = Data()
        body.appendFormField(name: "cleanup_mode", value: cleanupMode.rawValue, boundary: boundary)
        if let modelID = configuration.modelID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !modelID.isEmpty {
            body.appendFormField(name: "model_id", value: modelID, boundary: boundary)
        }
        body.appendFormField(name: "return_cleaned", value: returnCleaned ? "true" : "false", boundary: boundary)
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")
        return body
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
