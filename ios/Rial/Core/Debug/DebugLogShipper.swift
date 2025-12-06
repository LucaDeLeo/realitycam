//
//  DebugLogShipper.swift
//  Rial
//
//  Created by RealityCam on 2025-12-05.
//
//  Batch uploads debug log entries to backend.
//  Uses dedicated URLSession to avoid circular logging through APIClient.
//  All code is wrapped in #if DEBUG for zero production impact.
//

import Foundation
import os.log

#if DEBUG

/// Batch uploads debug log entries to backend.
///
/// Uses a dedicated URLSession instance (not APIClient) to avoid
/// circular logging when APIClient makes requests.
///
/// Errors are logged but never propagated - debug logging should
/// never impact app functionality or crash the app.
actor DebugLogShipper {
    private static let logger = Logger(subsystem: "app.rial", category: "debug-shipper")

    /// URLSession for debug log requests (separate from main APIClient)
    private let session: URLSession

    /// Base URL for API requests
    private let baseURL: URL

    /// JSON encoder configured for API (ISO8601 dates)
    /// Note: No keyEncodingStrategy needed - DebugLogEntry has explicit CodingKeys
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Creates a new debug log shipper.
    ///
    /// - Parameter baseURL: Base URL for the backend API
    init(baseURL: URL) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
        self.session = URLSession(configuration: config)
    }

    /// Ship batch of log entries to backend.
    ///
    /// Errors are logged but not propagated. Debug logging should
    /// never crash the app or impact normal functionality.
    ///
    /// - Parameter entries: Array of debug log entries to ship
    func ship(_ entries: [DebugLogEntry]) async {
        guard !entries.isEmpty else { return }

        let url = baseURL.appendingPathComponent("debug/logs")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        do {
            request.httpBody = try encoder.encode(entries)
        } catch {
            Self.logger.error("Failed to encode debug log entries: \(error.localizedDescription)")
            return
        }

        do {
            let (_, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 201 {
                    Self.logger.info("Shipped \(entries.count) log entries successfully")
                } else {
                    Self.logger.warning("Debug log ship returned status \(httpResponse.statusCode)")
                }
            }
        } catch {
            // Silently fail - debug logging should never impact app functionality
            // This is expected to fail if backend is not running or unreachable
            Self.logger.debug("Debug log ship failed (expected if backend not running): \(error.localizedDescription)")
        }
    }
}

#endif
