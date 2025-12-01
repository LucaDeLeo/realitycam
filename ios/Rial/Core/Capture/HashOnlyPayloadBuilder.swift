//
//  HashOnlyPayloadBuilder.swift
//  Rial
//
//  Created by RealityCam on 2025-12-01.
//
//  Builder for hash-only capture payloads (Story 8-3).
//  Constructs HashOnlyCapturePayload from CaptureData with privacy settings applied.
//

import Foundation
import os.log

// MARK: - HashOnlyPayloadBuilder

/// Builder for constructing hash-only capture payloads.
///
/// Takes CaptureData and privacy settings to produce a HashOnlyCapturePayload
/// suitable for privacy mode uploads.
///
/// ## Payload Construction
/// 1. Computes SHA-256 hash of JPEG bytes (mediaHash)
/// 2. Filters metadata according to privacy settings
/// 3. Builds metadata flags
/// 4. Assembles complete payload
///
/// The assertion is set to empty and must be added by the caller after signing.
///
/// ## Usage
/// ```swift
/// let payload = await HashOnlyPayloadBuilder.build(
///     from: captureData,
///     privacySettings: settings,
///     depthAnalysis: depthResult
/// )
///
/// // Sign the payload
/// let hash = CryptoService.sha256Data(try payload.toJSONData())
/// let assertion = try await assertionService.generateAssertion(for: hash)
/// payload.assertion = assertion.base64EncodedString()
///
/// // Upload payload
/// await uploadHashOnlyPayload(payload)
/// ```
public enum HashOnlyPayloadBuilder {

    // MARK: - Logger

    private static let logger = Logger(subsystem: "app.rial", category: "payloadbuilder")

    // MARK: - Build Methods

    /// Builds a hash-only payload from capture data.
    ///
    /// - Parameters:
    ///   - captureData: Original capture data containing JPEG, depth, metadata
    ///   - privacySettings: Privacy settings to apply for metadata filtering
    ///   - depthAnalysis: Client-side depth analysis result
    /// - Returns: HashOnlyCapturePayload ready for signing
    ///
    /// ## Example
    /// ```swift
    /// let payload = await HashOnlyPayloadBuilder.build(
    ///     from: captureData,
    ///     privacySettings: settings,
    ///     depthAnalysis: depthResult
    /// )
    /// ```
    public static func build(
        from captureData: CaptureData,
        privacySettings: PrivacySettings,
        depthAnalysis: DepthAnalysisResult
    ) async -> HashOnlyCapturePayload {
        let startTime = CFAbsoluteTimeGetCurrent()

        // 1. Compute media hash (SHA-256 of JPEG bytes)
        let mediaHash = CryptoService.sha256(captureData.jpeg)
        logger.debug("Computed mediaHash: \(mediaHash.prefix(16))...")

        // 2. Filter metadata according to privacy settings
        let filteredMetadata = await MetadataFilterService.filterAll(
            captureData: captureData,
            settings: privacySettings
        )
        logger.debug("Filtered metadata: location=\(filteredMetadata.location != nil), timestamp=\(filteredMetadata.timestamp != nil), device=\(filteredMetadata.deviceModel != nil)")

        // 3. Build metadata flags
        let metadataFlags = MetadataFilterService.buildFlags(from: privacySettings)

        // 4. Assemble payload (assertion added later after signing)
        let payload = HashOnlyCapturePayload(
            mediaHash: mediaHash,
            depthAnalysis: depthAnalysis,
            metadata: filteredMetadata,
            metadataFlags: metadataFlags,
            capturedAt: captureData.timestamp,
            assertion: "" // Set after signing
        )

        let buildTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        logger.info("Hash-only payload built in \(String(format: "%.1f", buildTime))ms")

        // Verify payload size
        if let size = payload.serializedSize() {
            logger.info("Payload size: \(size) bytes (limit: \(HashOnlyCapturePayload.maxPayloadSize) bytes)")

            if size >= HashOnlyCapturePayload.maxPayloadSize {
                logger.warning("Payload exceeds 10KB limit: \(size) bytes")
            }
        }

        return payload
    }

    /// Builds a hash-only payload synchronously (for cases where async isn't available).
    ///
    /// Note: Location filtering with coarse level may not work correctly in sync mode.
    /// Use the async version when possible.
    ///
    /// - Parameters:
    ///   - captureData: Original capture data
    ///   - privacySettings: Privacy settings to apply
    ///   - depthAnalysis: Client-side depth analysis result
    /// - Returns: HashOnlyCapturePayload ready for signing
    public static func buildSync(
        from captureData: CaptureData,
        privacySettings: PrivacySettings,
        depthAnalysis: DepthAnalysisResult
    ) -> HashOnlyCapturePayload {
        let startTime = CFAbsoluteTimeGetCurrent()

        // 1. Compute media hash
        let mediaHash = CryptoService.sha256(captureData.jpeg)

        // 2. Filter metadata (sync version)
        let filteredLocation = MetadataFilterService.filterLocationSync(
            data: captureData.metadata.location,
            level: privacySettings.locationLevel
        )
        let filteredTimestamp = MetadataFilterService.filterTimestamp(
            date: captureData.timestamp,
            level: privacySettings.timestampLevel
        )
        let filteredDevice = MetadataFilterService.filterDeviceInfo(
            metadata: captureData.metadata,
            level: privacySettings.deviceInfoLevel
        )

        let filteredMetadata = FilteredMetadata(
            location: filteredLocation,
            timestamp: filteredTimestamp,
            deviceModel: filteredDevice
        )

        // 3. Build metadata flags
        let metadataFlags = MetadataFilterService.buildFlags(from: privacySettings)

        // 4. Assemble payload
        let payload = HashOnlyCapturePayload(
            mediaHash: mediaHash,
            depthAnalysis: depthAnalysis,
            metadata: filteredMetadata,
            metadataFlags: metadataFlags,
            capturedAt: captureData.timestamp,
            assertion: ""
        )

        let buildTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        logger.info("Hash-only payload built (sync) in \(String(format: "%.1f", buildTime))ms")

        return payload
    }

    // MARK: - Video Payload Building

    /// Builds a hash-only payload for video capture.
    ///
    /// - Parameters:
    ///   - captureData: Original capture data
    ///   - privacySettings: Privacy settings to apply
    ///   - temporalDepthAnalysis: Client-side temporal depth analysis result for video
    ///   - hashChain: Video hash chain data
    ///   - frameCount: Number of frames in video
    ///   - durationMs: Video duration in milliseconds
    /// - Returns: HashOnlyCapturePayload for video
    public static func buildVideo(
        from captureData: CaptureData,
        privacySettings: PrivacySettings,
        temporalDepthAnalysis: TemporalDepthAnalysisResult,
        hashChain: PrivacyHashChainData,
        frameCount: Int,
        durationMs: Int
    ) async -> HashOnlyCapturePayload {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Compute media hash (for video, hash of video bytes)
        let mediaHash = CryptoService.sha256(captureData.jpeg) // Note: video bytes

        // Filter metadata
        let filteredMetadata = await MetadataFilterService.filterAll(
            captureData: captureData,
            settings: privacySettings
        )

        // Build metadata flags
        let metadataFlags = MetadataFilterService.buildFlags(from: privacySettings)

        // Assemble video payload
        let payload = HashOnlyCapturePayload(
            mediaHash: mediaHash,
            temporalDepthAnalysis: temporalDepthAnalysis,
            metadata: filteredMetadata,
            metadataFlags: metadataFlags,
            capturedAt: captureData.timestamp,
            assertion: "",
            hashChain: hashChain,
            frameCount: frameCount,
            durationMs: durationMs
        )

        let buildTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        logger.info("Video hash-only payload built in \(String(format: "%.1f", buildTime))ms")

        return payload
    }
}

// MARK: - Payload Signing Helper

extension HashOnlyPayloadBuilder {

    /// Signs a hash-only payload using the assertion service.
    ///
    /// Computes SHA-256 of the serialized payload JSON and generates
    /// a DCAppAttest assertion covering the hash.
    ///
    /// - Parameters:
    ///   - payload: Payload to sign (assertion will be set)
    ///   - assertionService: Service for generating assertions
    /// - Returns: Signed payload with assertion set
    /// - Throws: CaptureAssertionError if signing fails
    ///
    /// ## Example
    /// ```swift
    /// var payload = await HashOnlyPayloadBuilder.build(from: captureData, ...)
    /// payload = try await HashOnlyPayloadBuilder.sign(
    ///     payload: payload,
    ///     with: assertionService
    /// )
    /// ```
    static func sign(
        payload: HashOnlyCapturePayload,
        with assertionService: CaptureAssertionService
    ) async throws -> HashOnlyCapturePayload {
        var signedPayload = payload

        // Serialize payload to JSON for hashing
        let jsonData = try payload.toJSONData()
        logger.debug("Serialized payload for signing: \(jsonData.count) bytes")

        // Compute SHA-256 of serialized payload
        let payloadHash = CryptoService.sha256Data(jsonData)

        // Generate assertion from Secure Enclave
        let assertion = try await assertionService.generateAssertion(for: payloadHash)

        // Set assertion as Base64 string
        signedPayload.assertion = assertion.base64EncodedString()

        logger.info("Payload signed, assertion size: \(assertion.count) bytes")

        return signedPayload
    }
}
