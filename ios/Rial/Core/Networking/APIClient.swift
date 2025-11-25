//
//  APIClient.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  URLSession-based API client with device authentication.
//

import Foundation
import os.log

/// HTTP API client with device authentication.
///
/// Provides a centralized interface for making authenticated API requests
/// to the RealityCam backend. Handles TLS 1.3, device signatures, and
/// standard error handling.
///
/// ## Features
/// - Device authentication via Ed25519 signatures
/// - JSON encoding/decoding with proper date handling
/// - Comprehensive error handling and logging
/// - Configurable base URL for dev/prod environments
///
/// ## Usage
/// ```swift
/// let client = APIClient(baseURL: URL(string: "https://backend-production-5e5a.up.railway.app")!)
///
/// // Register device
/// let response: DeviceRegistrationResponse = try await client.post(
///     path: "/api/v1/devices",
///     body: registrationRequest
/// )
/// ```
final class APIClient {
    private static let logger = Logger(subsystem: "app.rial", category: "api-client")

    /// Base URL for API requests
    let baseURL: URL

    /// Device signature service (optional - some endpoints don't require auth)
    private let deviceSignature: DeviceSignature?

    /// URLSession for standard requests
    private let session: URLSession

    /// JSON encoder configured for API
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    /// JSON decoder configured for API
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    // MARK: - Initialization

    /// Creates a new API client.
    ///
    /// - Parameters:
    ///   - baseURL: Base URL for API requests
    ///   - deviceSignature: Optional device signature service for authenticated requests
    init(baseURL: URL, deviceSignature: DeviceSignature? = nil) {
        self.baseURL = baseURL
        self.deviceSignature = deviceSignature

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "Rial-iOS/\(Self.appVersion)"
        ]

        self.session = URLSession(configuration: config)
    }

    // MARK: - Request Methods

    /// Perform a GET request.
    ///
    /// - Parameters:
    ///   - path: API path (e.g., "/api/v1/devices")
    ///   - authenticated: Whether to include device signature (default: true)
    /// - Returns: Decoded response
    func get<T: Decodable>(path: String, authenticated: Bool = true) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"

        if authenticated {
            try deviceSignature?.sign(&request)
        }

        return try await perform(request)
    }

    /// Perform a POST request.
    ///
    /// - Parameters:
    ///   - path: API path
    ///   - body: Request body (will be JSON-encoded)
    ///   - authenticated: Whether to include device signature (default: true)
    /// - Returns: Decoded response
    func post<T: Decodable, B: Encodable>(
        path: String,
        body: B,
        authenticated: Bool = true
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        if authenticated {
            try deviceSignature?.sign(&request)
        }

        return try await perform(request)
    }

    /// Perform a POST request without expecting a response body.
    ///
    /// - Parameters:
    ///   - path: API path
    ///   - body: Request body (will be JSON-encoded)
    ///   - authenticated: Whether to include device signature (default: true)
    func post<B: Encodable>(
        path: String,
        body: B,
        authenticated: Bool = true
    ) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        if authenticated {
            try deviceSignature?.sign(&request)
        }

        try await performNoContent(request)
    }

    /// Perform raw request (used for multipart uploads).
    ///
    /// - Parameter request: Configured URLRequest
    /// - Returns: Decoded response
    func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        Self.logger.debug("Request: \(request.httpMethod ?? "?") \(request.url?.path ?? "?")")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        Self.logger.debug("Response: \(httpResponse.statusCode) (\(data.count) bytes)")

        try validateResponse(httpResponse, data: data)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Self.logger.error("Decode error: \(error.localizedDescription)")
            throw APIError.decodeFailed(error)
        }
    }

    /// Perform request expecting no content (204).
    private func performNoContent(_ request: URLRequest) async throws {
        Self.logger.debug("Request: \(request.httpMethod ?? "?") \(request.url?.path ?? "?")")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        Self.logger.debug("Response: \(httpResponse.statusCode)")

        try validateResponse(httpResponse, data: data)
    }

    // MARK: - Private Methods

    /// Validate HTTP response and throw appropriate errors.
    private func validateResponse(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200...299:
            return // Success

        case 400:
            throw APIError.badRequest(parseErrorMessage(from: data))

        case 401:
            throw APIError.unauthorized

        case 403:
            throw APIError.forbidden

        case 404:
            throw APIError.notFound

        case 409:
            throw APIError.conflict(parseErrorMessage(from: data))

        case 429:
            throw APIError.rateLimited

        case 500...599:
            throw APIError.serverError(response.statusCode)

        default:
            throw APIError.httpError(response.statusCode)
        }
    }

    /// Parse error message from response body.
    private func parseErrorMessage(from data: Data) -> String? {
        struct ErrorResponse: Decodable {
            let error: String?
            let message: String?
        }

        guard let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) else {
            return nil
        }

        return errorResponse.error ?? errorResponse.message
    }

    /// Get app version string.
    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - APIError

/// Errors that can occur during API requests.
enum APIError: Error, LocalizedError {
    /// Response is not HTTP response
    case invalidResponse

    /// Failed to encode request body
    case encodeFailed(Error)

    /// Failed to decode response body
    case decodeFailed(Error)

    /// HTTP 400 - Bad Request
    case badRequest(String?)

    /// HTTP 401 - Unauthorized (invalid/missing auth)
    case unauthorized

    /// HTTP 403 - Forbidden (valid auth but not permitted)
    case forbidden

    /// HTTP 404 - Not Found
    case notFound

    /// HTTP 409 - Conflict
    case conflict(String?)

    /// HTTP 429 - Rate Limited
    case rateLimited

    /// HTTP 5xx - Server Error
    case serverError(Int)

    /// Other HTTP error
    case httpError(Int)

    /// Network error (no connectivity, timeout, etc.)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .encodeFailed(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .decodeFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .badRequest(let message):
            return message ?? "Bad request"
        case .unauthorized:
            return "Device not authorized"
        case .forbidden:
            return "Access forbidden"
        case .notFound:
            return "Resource not found"
        case .conflict(let message):
            return message ?? "Conflict"
        case .rateLimited:
            return "Rate limited - please try again later"
        case .serverError(let code):
            return "Server error (\(code))"
        case .httpError(let code):
            return "HTTP error (\(code))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }

    /// Whether this error should be retried
    var isRetryable: Bool {
        switch self {
        case .serverError, .rateLimited, .networkError:
            return true
        default:
            return false
        }
    }
}
