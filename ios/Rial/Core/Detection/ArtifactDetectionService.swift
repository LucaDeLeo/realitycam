//
//  ArtifactDetectionService.swift
//  Rial
//
//  Created by RealityCam on 2025-12-11.
//
//  Artifact detection service for PWM, specular, and halftone patterns (Story 9-3).
//  Detects visual artifacts indicating screen recapture or printed photo.
//

import Foundation
import CoreGraphics
import CoreVideo
import Accelerate
import os.log

// MARK: - ArtifactDetectionService

/// Service for detecting visual artifacts in captured images.
///
/// ## Algorithm Overview
/// Detects three types of artifacts indicating recaptured images:
///
/// 1. **PWM Flicker (Screens):** Rolling shutter captures different phases of
///    PWM brightness control, creating horizontal banding at refresh rate frequencies.
///
/// 2. **Specular Reflections (Screens):** Screen glass creates rectangular,
///    uniform highlight patterns distinct from natural specular highlights.
///
/// 3. **Halftone Patterns (Prints):** CMYK printing creates periodic dot patterns
///    (rosette) detectable via FFT frequency analysis.
///
/// ## Performance
/// - Target: 50ms on iPhone 12 Pro+
/// - Acceptable: <100ms
/// - Memory: <75MB during analysis
///
/// ## Security Note
/// Per PRD research, artifact detection alone is vulnerable to Chimera attacks.
/// This is a SUPPORTING signal (15% weight), not PRIMARY (LiDAR is primary).
/// Always cross-validate with other detection methods.
///
/// ## Usage
/// ```swift
/// let result = await ArtifactDetectionService.shared.analyze(image: cgImage)
/// if result.isLikelyArtificial {
///     // Potential recapture detected
/// }
/// ```
///
/// ## Thread Safety
/// This class is marked `@unchecked Sendable` because:
/// 1. FFT setup is protected by a serial queue
/// 2. Public API uses async/await with work dispatched to background queues
/// 3. All analysis operations use local state only
public final class ArtifactDetectionService: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared singleton instance
    public static let shared = ArtifactDetectionService()

    // MARK: - Properties

    /// Logger for artifact detection events
    private static let logger = Logger(subsystem: "app.rial", category: "artifactdetection")

    /// Signpost log for performance tracking
    private static let signpostLog = OSLog(subsystem: "app.rial", category: .pointsOfInterest)

    /// Cached FFT setup for reuse (significant performance gain)
    /// Protected by `fftSetupQueue` for thread safety
    private var cachedFFTSetup: FFTSetup?
    private var cachedLog2n: vDSP_Length = 0

    /// Serial queue for FFT setup access
    private let fftSetupQueue = DispatchQueue(label: "app.rial.artifactdetection.fftsetup")

    // MARK: - Initialization

    /// Private initializer for singleton pattern
    private init() {
        Self.logger.debug("ArtifactDetectionService initialized")
    }

    deinit {
        // Clean up cached FFT setup
        if let setup = cachedFFTSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    // MARK: - Public API

    /// Analyzes a CGImage for visual artifacts.
    ///
    /// - Parameter image: CGImage to analyze
    /// - Returns: ArtifactAnalysisResult with detection results
    public func analyze(image: CGImage) async -> ArtifactAnalysisResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performAnalysis(image: image)
                continuation.resume(returning: result)
            }
        }
    }

    /// Analyzes a CVPixelBuffer for visual artifacts.
    ///
    /// - Parameter pixelBuffer: CVPixelBuffer to analyze (RGB, BGRA, or YCbCr)
    /// - Returns: ArtifactAnalysisResult with detection results
    public func analyze(pixelBuffer: CVPixelBuffer) async -> ArtifactAnalysisResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performAnalysis(pixelBuffer: pixelBuffer)
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Internal Analysis

    /// Performs artifact analysis on a CGImage.
    private func performAnalysis(image: CGImage) -> ArtifactAnalysisResult {
        let signpostID = OSSignpostID(log: Self.signpostLog)
        os_signpost(.begin, log: Self.signpostLog, name: "ArtifactAnalysis", signpostID: signpostID)
        defer {
            os_signpost(.end, log: Self.signpostLog, name: "ArtifactAnalysis", signpostID: signpostID)
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        let width = image.width
        let height = image.height

        guard width >= ArtifactAnalysisConstants.minImageDimension,
              height >= ArtifactAnalysisConstants.minImageDimension else {
            Self.logger.error("Image too small: \(width)x\(height)")
            return .unavailable()
        }

        Self.logger.debug("Analyzing image for artifacts: \(width)x\(height)")

        // Extract image data for analysis
        guard let imageData = extractImageData(from: image) else {
            Self.logger.error("Failed to extract image data")
            return .unavailable()
        }

        return analyzeImageData(
            imageData: imageData,
            startTime: startTime
        )
    }

    /// Performs artifact analysis on a CVPixelBuffer.
    private func performAnalysis(pixelBuffer: CVPixelBuffer) -> ArtifactAnalysisResult {
        let signpostID = OSSignpostID(log: Self.signpostLog)
        os_signpost(.begin, log: Self.signpostLog, name: "ArtifactAnalysis", signpostID: signpostID)
        defer {
            os_signpost(.end, log: Self.signpostLog, name: "ArtifactAnalysis", signpostID: signpostID)
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard width >= ArtifactAnalysisConstants.minImageDimension,
              height >= ArtifactAnalysisConstants.minImageDimension else {
            Self.logger.error("Image too small: \(width)x\(height)")
            return .unavailable()
        }

        Self.logger.debug("Analyzing pixel buffer for artifacts: \(width)x\(height)")

        guard let imageData = extractImageData(from: pixelBuffer) else {
            Self.logger.error("Failed to extract pixel buffer data")
            return .unavailable()
        }

        return analyzeImageData(
            imageData: imageData,
            startTime: startTime
        )
    }

    /// Common analysis pipeline for extracted image data.
    private func analyzeImageData(
        imageData: ImageData,
        startTime: CFAbsoluteTime
    ) -> ArtifactAnalysisResult {

        // Run all three detection algorithms
        let pwmResult = detectPWMFlicker(imageData: imageData)
        let specularResult = detectSpecularPatterns(imageData: imageData)
        let halftoneResult = detectHalftonePatterns(imageData: imageData)

        // Compute combined confidence
        let overallConfidence =
            pwmResult.confidence * ArtifactAnalysisConstants.pwmWeight +
            specularResult.confidence * ArtifactAnalysisConstants.specularWeight +
            halftoneResult.confidence * ArtifactAnalysisConstants.halftoneWeight

        // Determine if likely artificial
        let anyHighConfidence =
            pwmResult.confidence > ArtifactAnalysisConstants.highConfidenceThreshold ||
            specularResult.confidence > ArtifactAnalysisConstants.highConfidenceThreshold ||
            halftoneResult.confidence > ArtifactAnalysisConstants.highConfidenceThreshold

        let isLikelyArtificial =
            anyHighConfidence ||
            overallConfidence > ArtifactAnalysisConstants.combinedConfidenceThreshold

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let elapsedMs = Int64(elapsed * 1000)

        Self.logger.info("""
            Artifact analysis complete in \(elapsedMs)ms:
            PWM=\(pwmResult.detected) (\(String(format: "%.3f", pwmResult.confidence))),
            Specular=\(specularResult.detected) (\(String(format: "%.3f", specularResult.confidence))),
            Halftone=\(halftoneResult.detected) (\(String(format: "%.3f", halftoneResult.confidence))),
            Overall=\(String(format: "%.3f", overallConfidence)),
            isLikelyArtificial=\(isLikelyArtificial)
            """)

        if elapsedMs > ArtifactAnalysisConstants.maxTimeMs {
            Self.logger.warning("Artifact analysis exceeded \(ArtifactAnalysisConstants.maxTimeMs)ms target: \(elapsedMs)ms")
        }

        return ArtifactAnalysisResult(
            pwmFlickerDetected: pwmResult.detected,
            pwmConfidence: pwmResult.confidence,
            specularPatternDetected: specularResult.detected,
            specularConfidence: specularResult.confidence,
            halftoneDetected: halftoneResult.detected,
            halftoneConfidence: halftoneResult.confidence,
            overallConfidence: overallConfidence,
            isLikelyArtificial: isLikelyArtificial,
            analysisTimeMs: elapsedMs
        )
    }

    // MARK: - Image Data Extraction

    /// Holds image data for analysis
    private struct ImageData {
        let rgba: [UInt8]       // RGBA format, 4 bytes per pixel
        let luminance: [Float]  // Grayscale 0-1 normalized
        let width: Int
        let height: Int

        var pixelCount: Int { width * height }
    }

    /// Detection result from individual algorithm
    private struct DetectionResult {
        let detected: Bool
        let confidence: Float
    }

    /// Extracts RGBA and luminance data from CGImage.
    private func extractImageData(from image: CGImage) -> ImageData? {
        let width = image.width
        let height = image.height

        // Downsample if too large
        let targetWidth: Int
        let targetHeight: Int
        if width > ArtifactAnalysisConstants.maxImageDimension ||
           height > ArtifactAnalysisConstants.maxImageDimension {
            let scale = Float(ArtifactAnalysisConstants.targetImageDimension) / Float(max(width, height))
            targetWidth = max(ArtifactAnalysisConstants.minImageDimension, Int(Float(width) * scale))
            targetHeight = max(ArtifactAnalysisConstants.minImageDimension, Int(Float(height) * scale))
        } else {
            targetWidth = width
            targetHeight = height
        }

        // Create RGBA context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = targetWidth * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: targetHeight * bytesPerRow)

        guard let context = CGContext(
            data: &pixelData,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Self.logger.error("Failed to create CGContext")
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        // Compute luminance
        let pixelCount = targetWidth * targetHeight
        var luminance = [Float](repeating: 0, count: pixelCount)

        for i in 0..<pixelCount {
            let idx = i * 4
            let r = Float(pixelData[idx]) / 255.0
            let g = Float(pixelData[idx + 1]) / 255.0
            let b = Float(pixelData[idx + 2]) / 255.0
            // ITU-R BT.601 luma
            luminance[i] = 0.299 * r + 0.587 * g + 0.114 * b
        }

        return ImageData(
            rgba: pixelData,
            luminance: luminance,
            width: targetWidth,
            height: targetHeight
        )
    }

    /// Extracts RGBA and luminance data from CVPixelBuffer.
    private func extractImageData(from pixelBuffer: CVPixelBuffer) -> ImageData? {
        let lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        guard lockResult == kCVReturnSuccess else {
            Self.logger.error("Failed to lock pixel buffer: \(lockResult)")
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            Self.logger.error("Failed to get pixel buffer base address")
            return nil
        }

        let pixelCount = width * height
        var rgba = [UInt8](repeating: 0, count: pixelCount * 4)
        var luminance = [Float](repeating: 0, count: pixelCount)

        switch pixelFormat {
        case kCVPixelFormatType_32BGRA:
            let data = baseAddress.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)
            for y in 0..<height {
                for x in 0..<width {
                    let srcOffset = y * bytesPerRow + x * 4
                    let dstOffset = (y * width + x)
                    let rgbaOffset = dstOffset * 4

                    let b = data[srcOffset]
                    let g = data[srcOffset + 1]
                    let r = data[srcOffset + 2]
                    let a = data[srcOffset + 3]

                    rgba[rgbaOffset] = r
                    rgba[rgbaOffset + 1] = g
                    rgba[rgbaOffset + 2] = b
                    rgba[rgbaOffset + 3] = a

                    luminance[dstOffset] = (0.299 * Float(r) + 0.587 * Float(g) + 0.114 * Float(b)) / 255.0
                }
            }

        case kCVPixelFormatType_32RGBA:
            let data = baseAddress.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)
            for y in 0..<height {
                for x in 0..<width {
                    let srcOffset = y * bytesPerRow + x * 4
                    let dstOffset = (y * width + x)
                    let rgbaOffset = dstOffset * 4

                    rgba[rgbaOffset] = data[srcOffset]
                    rgba[rgbaOffset + 1] = data[srcOffset + 1]
                    rgba[rgbaOffset + 2] = data[srcOffset + 2]
                    rgba[rgbaOffset + 3] = data[srcOffset + 3]

                    luminance[dstOffset] = (0.299 * Float(rgba[rgbaOffset]) +
                                           0.587 * Float(rgba[rgbaOffset + 1]) +
                                           0.114 * Float(rgba[rgbaOffset + 2])) / 255.0
                }
            }

        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
                  let uvPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
                Self.logger.error("Failed to get YCbCr planes")
                return nil
            }

            let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let uvBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            let yData = yPlane.bindMemory(to: UInt8.self, capacity: height * yBytesPerRow)
            let uvData = uvPlane.bindMemory(to: UInt8.self, capacity: (height / 2) * uvBytesPerRow)

            for y in 0..<height {
                for x in 0..<width {
                    let yValue = Float(yData[y * yBytesPerRow + x])
                    let uvX = (x / 2) * 2
                    let uvY = y / 2
                    let uValue = Float(uvData[uvY * uvBytesPerRow + uvX]) - 128
                    let vValue = Float(uvData[uvY * uvBytesPerRow + uvX + 1]) - 128

                    let r = yValue + 1.402 * vValue
                    let g = yValue - 0.344136 * uValue - 0.714136 * vValue
                    let b = yValue + 1.772 * uValue

                    let dstOffset = y * width + x
                    let rgbaOffset = dstOffset * 4

                    rgba[rgbaOffset] = UInt8(clamping: Int(r))
                    rgba[rgbaOffset + 1] = UInt8(clamping: Int(g))
                    rgba[rgbaOffset + 2] = UInt8(clamping: Int(b))
                    rgba[rgbaOffset + 3] = 255

                    luminance[dstOffset] = yValue / 255.0
                }
            }

        default:
            Self.logger.error("Unsupported pixel format: \(pixelFormat)")
            return nil
        }

        return ImageData(rgba: rgba, luminance: luminance, width: width, height: height)
    }

    // MARK: - PWM Flicker Detection

    /// Detects PWM flicker patterns in the image.
    ///
    /// PWM (Pulse Width Modulation) creates horizontal banding when photographing
    /// screens due to rolling shutter capturing different phases of the PWM cycle.
    private func detectPWMFlicker(imageData: ImageData) -> DetectionResult {
        let width = imageData.width
        let height = imageData.height

        // Compute row-average luminance profile
        var rowAverages = [Float](repeating: 0, count: height)

        for y in 0..<height {
            var sum: Float = 0
            for x in 0..<width {
                sum += imageData.luminance[y * width + x]
            }
            rowAverages[y] = sum / Float(width)
        }

        // Compute mean and subtract for AC component
        var mean: Float = 0
        vDSP_meanv(rowAverages, 1, &mean, vDSP_Length(height))

        var centered = [Float](repeating: 0, count: height)
        var negMean = -mean
        vDSP_vsadd(rowAverages, 1, &negMean, &centered, 1, vDSP_Length(height))

        // Perform 1D FFT on luminance profile
        let log2n = vDSP_Length(ceil(log2(Float(height))))
        let fftSize = 1 << Int(log2n)

        // Get or create cached FFT setup (significant performance gain)
        let maybeFFTSetup: FFTSetup? = fftSetupQueue.sync {
            if cachedLog2n == log2n, let setup = cachedFFTSetup {
                return setup
            }

            // Destroy old setup if different size
            if let oldSetup = cachedFFTSetup {
                vDSP_destroy_fftsetup(oldSetup)
                cachedFFTSetup = nil
                cachedLog2n = 0
            }

            guard let newSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
                Self.logger.error("Failed to create FFT setup for PWM detection - low memory condition")
                return nil
            }

            cachedFFTSetup = newSetup
            cachedLog2n = log2n
            return newSetup
        }

        guard let fftSetup = maybeFFTSetup else {
            Self.logger.error("FFT setup unavailable for PWM detection")
            return DetectionResult(detected: false, confidence: 0)
        }

        // Allocate split complex arrays
        let halfN = fftSize / 2
        var realp = [Float](repeating: 0, count: halfN)
        var imagp = [Float](repeating: 0, count: halfN)

        // Pack real data into split complex (even/odd interleaving)
        for i in 0..<min(height / 2, halfN) {
            realp[i] = i * 2 < centered.count ? centered[i * 2] : 0
            imagp[i] = i * 2 + 1 < centered.count ? centered[i * 2 + 1] : 0
        }

        // Perform FFT using proper buffer management
        var magnitudes = [Float](repeating: 0, count: halfN)

        realp.withUnsafeMutableBufferPointer { realBuffer in
            imagp.withUnsafeMutableBufferPointer { imagBuffer in
                var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)

                // Perform FFT
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                // Compute magnitude spectrum
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }

        // Take square root for actual magnitude
        var sqrtMagnitudes = [Float](repeating: 0, count: halfN)
        var count = Int32(halfN)
        vvsqrtf(&sqrtMagnitudes, magnitudes, &count)

        // Normalize
        var maxMag: Float = 0
        vDSP_maxv(sqrtMagnitudes, 1, &maxMag, vDSP_Length(halfN))
        if maxMag > 0 {
            vDSP_vsdiv(sqrtMagnitudes, 1, &maxMag, &sqrtMagnitudes, 1, vDSP_Length(halfN))
        }

        // Compute noise floor (median of magnitudes)
        let sortedMags = sqrtMagnitudes.sorted()
        let medianMag = sortedMags[sortedMags.count / 2]
        let noiseThreshold = medianMag * ArtifactAnalysisConstants.minPWMBandStrength

        // Look for peaks at refresh rate frequencies
        var detectedBands = 0
        var totalPeakStrength: Float = 0

        for refreshRate in ArtifactAnalysisConstants.refreshRates {
            // Expected bin for this refresh rate
            let expectedBands = refreshRate / 2.0
            let expectedBin = Int(expectedBands * Float(fftSize) / Float(height))

            let tolerance = max(1, Int(Float(expectedBin) * ArtifactAnalysisConstants.pwmFrequencyTolerance))
            let searchStart = max(2, expectedBin - tolerance)
            let searchEnd = min(halfN - 1, expectedBin + tolerance)

            guard searchStart < searchEnd else { continue }

            // Find peak in this range
            var peakMag: Float = 0

            for bin in searchStart..<searchEnd {
                if sqrtMagnitudes[bin] > peakMag {
                    peakMag = sqrtMagnitudes[bin]
                }
            }

            // Check if peak is significant
            if peakMag > noiseThreshold && peakMag > ArtifactAnalysisConstants.halftoneMinPeakMagnitude {
                detectedBands += 1
                totalPeakStrength += peakMag
            }
        }

        let detected = detectedBands >= ArtifactAnalysisConstants.minPWMBandCount
        let avgPeakStrength = detectedBands > 0 ? totalPeakStrength / Float(detectedBands) : 0
        let confidence = min(1.0, avgPeakStrength * Float(detectedBands) / Float(ArtifactAnalysisConstants.refreshRates.count))

        Self.logger.debug("PWM detection: bands=\(detectedBands), avgStrength=\(String(format: "%.3f", avgPeakStrength)), confidence=\(String(format: "%.3f", confidence))")

        return DetectionResult(detected: detected, confidence: confidence)
    }

    // MARK: - Specular Reflection Detection

    /// Detects screen-like specular reflection patterns.
    ///
    /// Screen glass creates rectangular, uniform highlight patterns that differ
    /// from natural specular highlights (irregular, varied).
    private func detectSpecularPatterns(imageData: ImageData) -> DetectionResult {
        let width = imageData.width
        let height = imageData.height
        let pixelCount = width * height

        // Find highlight regions (high luminance, low saturation)
        var highlightMask = [Bool](repeating: false, count: pixelCount)
        var highlightCount = 0

        for i in 0..<pixelCount {
            let rgbaIdx = i * 4
            let r = Float(imageData.rgba[rgbaIdx]) / 255.0
            let g = Float(imageData.rgba[rgbaIdx + 1]) / 255.0
            let b = Float(imageData.rgba[rgbaIdx + 2]) / 255.0

            let luminance = imageData.luminance[i]

            // Compute saturation
            let maxRGB = max(r, max(g, b))
            let minRGB = min(r, min(g, b))
            let saturation = maxRGB > 0 ? (maxRGB - minRGB) / maxRGB : 0

            // Check if highlight
            if luminance >= ArtifactAnalysisConstants.highlightLuminanceThreshold &&
               saturation <= ArtifactAnalysisConstants.highlightSaturationThreshold {
                highlightMask[i] = true
                highlightCount += 1
            }
        }

        // Check highlight area fraction
        let areaFraction = Float(highlightCount) / Float(pixelCount)

        guard areaFraction >= ArtifactAnalysisConstants.minHighlightAreaFraction,
              areaFraction <= ArtifactAnalysisConstants.maxHighlightAreaFraction else {
            // Too few or too many highlights
            Self.logger.debug("Specular detection: highlight area \(String(format: "%.3f", areaFraction)) outside valid range")
            return DetectionResult(detected: false, confidence: 0)
        }

        // Simple connected component analysis using bounding box approach
        // Find bounding box of highlight region
        var minX = width, maxX = 0, minY = height, maxY = 0

        for y in 0..<height {
            for x in 0..<width {
                if highlightMask[y * width + x] {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX > minX && maxY > minY else {
            return DetectionResult(detected: false, confidence: 0)
        }

        let boundingWidth = maxX - minX + 1
        let boundingHeight = maxY - minY + 1
        let boundingArea = boundingWidth * boundingHeight

        // Compute rectangularity (how well highlights fill bounding box)
        let rectangularity = Float(highlightCount) / Float(boundingArea)

        // Compute aspect ratio
        let aspectRatio = Float(max(boundingWidth, boundingHeight)) / Float(min(boundingWidth, boundingHeight))

        // Check edge uniformity (how straight are the highlight edges)
        var edgeUniformityScore = computeEdgeUniformity(
            highlightMask: highlightMask,
            width: width,
            height: height,
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY
        )

        // Screen-like patterns have high rectangularity, significant aspect ratio, and uniform edges
        let isRectangular = rectangularity >= ArtifactAnalysisConstants.minRectangularity
        let hasAspectRatio = aspectRatio >= ArtifactAnalysisConstants.minAspectRatio
        let hasUniformEdges = edgeUniformityScore >= 0.5

        let detected = isRectangular && hasUniformEdges

        // Compute confidence based on how well pattern matches screen characteristics
        var confidence: Float = 0
        if rectangularity >= ArtifactAnalysisConstants.minRectangularity {
            confidence += rectangularity * 0.4
        }
        if hasAspectRatio {
            confidence += 0.2
        }
        confidence += edgeUniformityScore * 0.4

        // Reduce confidence for edge cases
        if areaFraction < 0.01 || areaFraction > 0.1 {
            confidence *= 0.7 // Penalize unusual area fractions
        }

        Self.logger.debug("Specular detection: rect=\(String(format: "%.3f", rectangularity)), aspect=\(String(format: "%.2f", aspectRatio)), edges=\(String(format: "%.3f", edgeUniformityScore)), confidence=\(String(format: "%.3f", confidence))")

        return DetectionResult(detected: detected, confidence: confidence)
    }

    /// Computes edge uniformity score for highlight region.
    private func computeEdgeUniformity(
        highlightMask: [Bool],
        width: Int,
        height: Int,
        minX: Int,
        maxX: Int,
        minY: Int,
        maxY: Int
    ) -> Float {
        // Sample edge positions and check variance
        var topEdge = [Int]()
        var bottomEdge = [Int]()
        var leftEdge = [Int]()
        var rightEdge = [Int]()

        // Find edge positions
        for x in minX...maxX {
            // Top edge: first y with highlight
            for y in minY...maxY {
                if highlightMask[y * width + x] {
                    topEdge.append(y)
                    break
                }
            }
            // Bottom edge: last y with highlight
            for y in stride(from: maxY, through: minY, by: -1) {
                if highlightMask[y * width + x] {
                    bottomEdge.append(y)
                    break
                }
            }
        }

        for y in minY...maxY {
            // Left edge
            for x in minX...maxX {
                if highlightMask[y * width + x] {
                    leftEdge.append(x)
                    break
                }
            }
            // Right edge
            for x in stride(from: maxX, through: minX, by: -1) {
                if highlightMask[y * width + x] {
                    rightEdge.append(x)
                    break
                }
            }
        }

        // Compute variance of each edge (low variance = straight edge)
        func edgeVariance(_ edge: [Int]) -> Float {
            guard edge.count > 1 else { return 0 }
            let mean = Float(edge.reduce(0, +)) / Float(edge.count)
            let variance = edge.reduce(0.0) { $0 + pow(Float($1) - mean, 2) } / Float(edge.count)
            return variance
        }

        let topVar = edgeVariance(topEdge)
        let bottomVar = edgeVariance(bottomEdge)
        let leftVar = edgeVariance(leftEdge)
        let rightVar = edgeVariance(rightEdge)

        // Average variance, normalized (lower is better)
        let avgVariance = (topVar + bottomVar + leftVar + rightVar) / 4.0
        let normalizedVariance = avgVariance / Float(max(maxX - minX, maxY - minY))

        // Convert to uniformity score (high = uniform)
        let uniformity = max(0, 1.0 - normalizedVariance * 10)

        return uniformity
    }

    // MARK: - Halftone Detection

    /// Detects halftone dot patterns from printed images.
    ///
    /// CMYK printing creates periodic dot patterns (rosette) at characteristic
    /// angles (15, 45, 75, 90 degrees) detectable via FFT.
    private func detectHalftonePatterns(imageData: ImageData) -> DetectionResult {
        let width = imageData.width
        let height = imageData.height

        let tileSize = ArtifactAnalysisConstants.halftoneTileSize
        var halftoneScores = [Float]()
        var tilesAnalyzed = 0

        // Analyze tiles across the image
        let strideX = max(tileSize, width / 4)
        let strideY = max(tileSize, height / 4)

        for tileY in stride(from: 0, to: height - tileSize, by: strideY) {
            for tileX in stride(from: 0, to: width - tileSize, by: strideX) {
                if let score = analyzeTileForHalftone(
                    imageData: imageData,
                    tileX: tileX,
                    tileY: tileY,
                    tileSize: tileSize
                ) {
                    if score > 0 {
                        halftoneScores.append(score)
                    }
                    tilesAnalyzed += 1
                }
            }
        }

        // Require minimum number of tiles with halftone pattern
        let detected = halftoneScores.count >= ArtifactAnalysisConstants.minHalftoneTiles

        // Compute confidence from average score of detected tiles
        let avgScore = halftoneScores.isEmpty ? 0 : halftoneScores.reduce(0, +) / Float(halftoneScores.count)
        let coverage = Float(halftoneScores.count) / Float(max(1, tilesAnalyzed))

        let confidence = detected ? min(1.0, avgScore * coverage * 2) : avgScore * 0.5

        Self.logger.debug("Halftone detection: tiles=\(halftoneScores.count)/\(tilesAnalyzed), avgScore=\(String(format: "%.3f", avgScore)), confidence=\(String(format: "%.3f", confidence))")

        return DetectionResult(detected: detected, confidence: confidence)
    }

    /// Analyzes a single tile for halftone patterns using simplified frequency analysis.
    ///
    /// Instead of full 2D FFT (memory-intensive), we use row/column autocorrelation
    /// to detect periodic patterns typical of halftone printing.
    private func analyzeTileForHalftone(
        imageData: ImageData,
        tileX: Int,
        tileY: Int,
        tileSize: Int
    ) -> Float? {
        let width = imageData.width

        // Extract tile data and compute statistics
        var tileData = [Float](repeating: 0, count: tileSize * tileSize)

        for y in 0..<tileSize {
            for x in 0..<tileSize {
                let srcIdx = (tileY + y) * width + (tileX + x)
                tileData[y * tileSize + x] = imageData.luminance[srcIdx]
            }
        }

        // Compute row-wise autocorrelation to detect horizontal periodicity
        var rowPeriodicity: Float = 0
        for y in 0..<tileSize {
            let rowStart = y * tileSize
            var rowAutocorr: Float = 0

            // Check for periodicity at halftone frequencies
            for lag in Int(ArtifactAnalysisConstants.halftoneMinFrequency)..<min(Int(ArtifactAnalysisConstants.halftoneMaxFrequency), tileSize / 2) {
                var correlation: Float = 0
                for x in 0..<(tileSize - lag) {
                    correlation += tileData[rowStart + x] * tileData[rowStart + x + lag]
                }
                correlation /= Float(tileSize - lag)
                rowAutocorr = max(rowAutocorr, abs(correlation))
            }
            rowPeriodicity += rowAutocorr
        }
        rowPeriodicity /= Float(tileSize)

        // Compute column-wise autocorrelation to detect vertical periodicity
        var colPeriodicity: Float = 0
        for x in 0..<tileSize {
            var colAutocorr: Float = 0

            for lag in Int(ArtifactAnalysisConstants.halftoneMinFrequency)..<min(Int(ArtifactAnalysisConstants.halftoneMaxFrequency), tileSize / 2) {
                var correlation: Float = 0
                for y in 0..<(tileSize - lag) {
                    correlation += tileData[y * tileSize + x] * tileData[(y + lag) * tileSize + x]
                }
                correlation /= Float(tileSize - lag)
                colAutocorr = max(colAutocorr, abs(correlation))
            }
            colPeriodicity += colAutocorr
        }
        colPeriodicity /= Float(tileSize)

        // Compute diagonal autocorrelation (45-degree rosette pattern)
        var diagPeriodicity: Float = 0
        let diagSamples = min(tileSize, tileSize) / 2
        for lag in Int(ArtifactAnalysisConstants.halftoneMinFrequency)..<min(Int(ArtifactAnalysisConstants.halftoneMaxFrequency), diagSamples) {
            var correlation: Float = 0
            var count = 0
            for y in 0..<(tileSize - lag) {
                for x in 0..<(tileSize - lag) {
                    correlation += tileData[y * tileSize + x] * tileData[(y + lag) * tileSize + x + lag]
                    count += 1
                }
            }
            if count > 0 {
                correlation /= Float(count)
                diagPeriodicity = max(diagPeriodicity, abs(correlation))
            }
        }

        // Halftone has strong periodicity in multiple directions (rosette pattern)
        let combinedScore = (rowPeriodicity + colPeriodicity + diagPeriodicity) / 3.0

        // Normalize score
        var mean: Float = 0
        vDSP_meanv(tileData, 1, &mean, vDSP_Length(tileSize * tileSize))

        var variance: Float = 0
        var tileDataCopy = tileData
        var negMean = -mean
        vDSP_vsadd(tileData, 1, &negMean, &tileDataCopy, 1, vDSP_Length(tileSize * tileSize))
        vDSP_dotpr(tileDataCopy, 1, tileDataCopy, 1, &variance, vDSP_Length(tileSize * tileSize))
        variance /= Float(tileSize * tileSize)

        // Normalize by variance to get relative periodicity strength
        let normalizedScore = variance > 0.001 ? combinedScore / sqrt(variance) : 0

        return normalizedScore > 0.5 ? normalizedScore * 0.3 : 0
    }
}
