//
//  TextureClassificationService.swift
//  Rial
//
//  Created by RealityCam on 2025-12-11.
//
//  Texture classification service using heuristic analysis (Story 9-2).
//  Distinguishes real materials from screen/print surfaces.
//
//  MVP Implementation: Uses image statistics heuristics (color variance,
//  edge patterns, periodicity) to classify textures. Interface is designed
//  for future CoreML model integration.
//

import Foundation
import CoreGraphics
import CoreVideo
import Accelerate
import os.log

// MARK: - TextureClassificationService

/// Service for classifying surface textures to detect recaptured images.
///
/// ## Algorithm Overview (Heuristic MVP)
/// This service analyzes image statistics to distinguish real-world scenes
/// from photos of screens or printed materials:
///
/// 1. **Color Analysis**: Screens have more uniform color distributions
/// 2. **Edge Analysis**: Prints have softer edges due to ink spread
/// 3. **Frequency Analysis**: Screens show pixel grid periodicity
/// 4. **Texture Analysis**: Real scenes have natural texture variations
///
/// ## Future: CoreML Integration
/// The interface is designed for drop-in replacement with a trained CoreML
/// model (MobileNetV3 or similar) for higher accuracy classification.
///
/// ## Performance
/// - Target: 15ms on iPhone 12 Pro+
/// - Acceptable: <50ms
/// - Memory: <50MB during analysis
///
/// ## Security Note
/// Per PRD research, texture classification alone is vulnerable to Chimera attacks.
/// This is a SUPPORTING signal (15% weight), not PRIMARY (LiDAR is primary).
/// Always cross-validate with other detection methods.
///
/// ## Usage
/// ```swift
/// let result = await TextureClassificationService.shared.classify(image: cgImage)
/// if result.isLikelyRecaptured {
///     // Potential recapture detected
/// }
/// ```
///
/// ## Thread Safety
/// This class is marked `@unchecked Sendable` because:
/// 1. All analysis operations are stateless and performed on background queues
/// 2. Public API uses async/await with work dispatched to background queues
/// 3. No mutable shared state between calls
public final class TextureClassificationService: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared singleton instance
    public static let shared = TextureClassificationService()

    // MARK: - Properties

    /// Logger for texture classification events
    private static let logger = Logger(subsystem: "app.rial", category: "textureclassification")

    /// Signpost log for performance tracking
    private static let signpostLog = OSLog(subsystem: "app.rial", category: .pointsOfInterest)

    // MARK: - Initialization

    /// Private initializer for singleton pattern
    private init() {
        Self.logger.debug("TextureClassificationService initialized")
    }

    // MARK: - Public API

    /// Classifies texture in a CGImage.
    ///
    /// - Parameter image: CGImage to analyze
    /// - Returns: TextureClassificationResult with classification results
    public func classify(image: CGImage) async -> TextureClassificationResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performClassification(image: image)
                continuation.resume(returning: result)
            }
        }
    }

    /// Classifies texture in a CVPixelBuffer.
    ///
    /// - Parameter pixelBuffer: CVPixelBuffer to analyze (RGB, BGRA, or YCbCr)
    /// - Returns: TextureClassificationResult with classification results
    public func classify(pixelBuffer: CVPixelBuffer) async -> TextureClassificationResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performClassification(pixelBuffer: pixelBuffer)
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Internal Analysis

    /// Performs texture classification on a CGImage.
    private func performClassification(image: CGImage) -> TextureClassificationResult {
        let signpostID = OSSignpostID(log: Self.signpostLog)
        os_signpost(.begin, log: Self.signpostLog, name: "TextureClassification", signpostID: signpostID)
        defer {
            os_signpost(.end, log: Self.signpostLog, name: "TextureClassification", signpostID: signpostID)
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Validate image dimensions
        let width = image.width
        let height = image.height

        guard width >= TextureClassificationConstants.minImageDimension,
              height >= TextureClassificationConstants.minImageDimension else {
            Self.logger.error("Image too small: \(width)x\(height)")
            return .unavailable(reason: "Image too small: \(width)x\(height), minimum: \(TextureClassificationConstants.minImageDimension)")
        }

        Self.logger.debug("Classifying image: \(width)x\(height)")

        // Extract RGBA data for analysis
        guard let imageData = extractImageData(from: image) else {
            Self.logger.error("Failed to extract image data")
            return .unavailable(reason: "Failed to extract image data")
        }

        // Perform heuristic analysis
        return analyzeTexture(
            imageData: imageData,
            width: width,
            height: height,
            startTime: startTime
        )
    }

    /// Performs texture classification on a CVPixelBuffer.
    private func performClassification(pixelBuffer: CVPixelBuffer) -> TextureClassificationResult {
        let signpostID = OSSignpostID(log: Self.signpostLog)
        os_signpost(.begin, log: Self.signpostLog, name: "TextureClassification", signpostID: signpostID)
        defer {
            os_signpost(.end, log: Self.signpostLog, name: "TextureClassification", signpostID: signpostID)
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard width >= TextureClassificationConstants.minImageDimension,
              height >= TextureClassificationConstants.minImageDimension else {
            Self.logger.error("Image too small: \(width)x\(height)")
            return .unavailable(reason: "Image too small: \(width)x\(height)")
        }

        Self.logger.debug("Classifying pixel buffer: \(width)x\(height)")

        // Extract RGBA data from pixel buffer
        guard let imageData = extractImageData(from: pixelBuffer) else {
            Self.logger.error("Failed to extract pixel buffer data")
            return .unavailable(reason: "Failed to extract pixel buffer data")
        }

        return analyzeTexture(
            imageData: imageData,
            width: width,
            height: height,
            startTime: startTime
        )
    }

    // MARK: - Image Data Extraction

    /// Holds RGBA image data for analysis
    private struct ImageData {
        let rgba: [UInt8]  // RGBA format, 4 bytes per pixel
        let width: Int
        let height: Int

        var pixelCount: Int { width * height }
    }

    /// Extracts RGBA data from CGImage.
    private func extractImageData(from image: CGImage) -> ImageData? {
        let width = image.width
        let height = image.height

        // Downsample if too large
        let targetWidth: Int
        let targetHeight: Int
        if width > TextureClassificationConstants.maxImageDimension ||
           height > TextureClassificationConstants.maxImageDimension {
            let scale = Float(TextureClassificationConstants.targetImageSize) / Float(max(width, height))
            targetWidth = max(TextureClassificationConstants.minImageDimension, Int(Float(width) * scale))
            targetHeight = max(TextureClassificationConstants.minImageDimension, Int(Float(height) * scale))
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
            Self.logger.error("Failed to create CGContext for image extraction")
            return nil
        }

        // Draw image
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        return ImageData(rgba: pixelData, width: targetWidth, height: targetHeight)
    }

    /// Extracts RGBA data from CVPixelBuffer.
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

        var rgba = [UInt8](repeating: 0, count: width * height * 4)

        switch pixelFormat {
        case kCVPixelFormatType_32BGRA:
            let data = baseAddress.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)
            for y in 0..<height {
                for x in 0..<width {
                    let srcOffset = y * bytesPerRow + x * 4
                    let dstOffset = (y * width + x) * 4
                    rgba[dstOffset] = data[srcOffset + 2]     // R
                    rgba[dstOffset + 1] = data[srcOffset + 1] // G
                    rgba[dstOffset + 2] = data[srcOffset]     // B
                    rgba[dstOffset + 3] = data[srcOffset + 3] // A
                }
            }

        case kCVPixelFormatType_32RGBA:
            let data = baseAddress.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)
            for y in 0..<height {
                for x in 0..<width {
                    let srcOffset = y * bytesPerRow + x * 4
                    let dstOffset = (y * width + x) * 4
                    rgba[dstOffset] = data[srcOffset]
                    rgba[dstOffset + 1] = data[srcOffset + 1]
                    rgba[dstOffset + 2] = data[srcOffset + 2]
                    rgba[dstOffset + 3] = data[srcOffset + 3]
                }
            }

        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            // YCbCr format - convert to RGB
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

                    // YCbCr to RGB conversion
                    let r = yValue + 1.402 * vValue
                    let g = yValue - 0.344136 * uValue - 0.714136 * vValue
                    let b = yValue + 1.772 * uValue

                    let dstOffset = (y * width + x) * 4
                    rgba[dstOffset] = UInt8(clamping: Int(r))
                    rgba[dstOffset + 1] = UInt8(clamping: Int(g))
                    rgba[dstOffset + 2] = UInt8(clamping: Int(b))
                    rgba[dstOffset + 3] = 255
                }
            }

        default:
            Self.logger.error("Unsupported pixel format: \(pixelFormat)")
            return nil
        }

        return ImageData(rgba: rgba, width: width, height: height)
    }

    // MARK: - Heuristic Analysis

    /// Analyzes texture using heuristic features.
    private func analyzeTexture(
        imageData: ImageData,
        width: Int,
        height: Int,
        startTime: CFAbsoluteTime
    ) -> TextureClassificationResult {

        // Extract features
        let colorVariance = computeColorVariance(imageData: imageData)
        let edgeSharpness = computeEdgeSharpness(imageData: imageData)
        let periodicity = computePeriodicity(imageData: imageData)
        let highFreqContent = computeHighFrequencyContent(imageData: imageData)
        let colorUniformity = computeColorUniformity(imageData: imageData)

        Self.logger.debug("""
            Texture features:
            colorVariance=\(String(format: "%.3f", colorVariance)),
            edgeSharpness=\(String(format: "%.3f", edgeSharpness)),
            periodicity=\(String(format: "%.3f", periodicity)),
            highFreqContent=\(String(format: "%.3f", highFreqContent)),
            colorUniformity=\(String(format: "%.3f", colorUniformity))
            """)

        // Compute classification scores
        var scores: [TextureType: Float] = [:]

        // Real scene: high texture variation, natural edges, varied colors
        let realSceneScore = computeRealSceneScore(
            colorVariance: colorVariance,
            edgeSharpness: edgeSharpness,
            periodicity: periodicity,
            highFreqContent: highFreqContent,
            colorUniformity: colorUniformity
        )
        scores[.realScene] = realSceneScore

        // LCD screen: uniform colors, pixel grid periodicity, sharp edges
        let lcdScore = computeLCDScreenScore(
            colorVariance: colorVariance,
            edgeSharpness: edgeSharpness,
            periodicity: periodicity,
            colorUniformity: colorUniformity
        )
        scores[.lcdScreen] = lcdScore

        // OLED screen: similar to LCD but different patterns
        let oledScore = computeOLEDScreenScore(
            colorVariance: colorVariance,
            edgeSharpness: edgeSharpness,
            periodicity: periodicity,
            colorUniformity: colorUniformity
        )
        scores[.oledScreen] = oledScore

        // Printed paper: soft edges, halftone patterns, limited color range
        let printScore = computePrintedPaperScore(
            colorVariance: colorVariance,
            edgeSharpness: edgeSharpness,
            periodicity: periodicity,
            highFreqContent: highFreqContent,
            colorUniformity: colorUniformity
        )
        scores[.printedPaper] = printScore

        // Unknown: low confidence in all classes
        scores[.unknown] = 0.1

        // Determine primary classification
        let (classification, confidence) = determineClassification(scores: scores)

        // Determine if likely recaptured
        let screenConfidence = max(lcdScore, oledScore)
        let isLikelyRecaptured = screenConfidence > TextureClassificationConstants.recaptureConfidenceThreshold ||
                                 printScore > TextureClassificationConstants.recaptureConfidenceThreshold

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let elapsedMs = Int(elapsed * 1000)

        Self.logger.info("""
            Texture classification complete in \(elapsedMs)ms:
            classification=\(classification.rawValue),
            confidence=\(String(format: "%.3f", confidence)),
            isLikelyRecaptured=\(isLikelyRecaptured)
            """)

        if elapsedMs > TextureClassificationConstants.maxTimeMs {
            Self.logger.warning("Texture classification exceeded \(TextureClassificationConstants.maxTimeMs)ms target: \(elapsedMs)ms")
        }

        return TextureClassificationResult(
            classification: classification,
            confidence: confidence,
            allClassifications: scores,
            isLikelyRecaptured: isLikelyRecaptured,
            analysisTimeMs: elapsedMs
        )
    }

    // MARK: - Feature Extraction

    /// Computes color variance across the image.
    /// Lower variance suggests more uniform colors (screen-like).
    private func computeColorVariance(imageData: ImageData) -> Float {
        var rSum: Float = 0, gSum: Float = 0, bSum: Float = 0
        var rSqSum: Float = 0, gSqSum: Float = 0, bSqSum: Float = 0

        let pixelCount = Float(imageData.pixelCount)

        for i in stride(from: 0, to: imageData.rgba.count, by: 4) {
            let r = Float(imageData.rgba[i]) / 255.0
            let g = Float(imageData.rgba[i + 1]) / 255.0
            let b = Float(imageData.rgba[i + 2]) / 255.0

            rSum += r
            gSum += g
            bSum += b

            rSqSum += r * r
            gSqSum += g * g
            bSqSum += b * b
        }

        // Variance = E[X^2] - E[X]^2
        let rMean = rSum / pixelCount
        let gMean = gSum / pixelCount
        let bMean = bSum / pixelCount

        let rVar = (rSqSum / pixelCount) - (rMean * rMean)
        let gVar = (gSqSum / pixelCount) - (gMean * gMean)
        let bVar = (bSqSum / pixelCount) - (bMean * bMean)

        // Average variance across channels, normalized to 0-1
        let avgVar = (rVar + gVar + bVar) / 3.0
        return min(1.0, avgVar * 4.0) // Scale up for sensitivity
    }

    /// Computes edge sharpness using Sobel-like gradient magnitude.
    /// Higher values indicate sharper edges (screens), lower values suggest soft edges (prints).
    private func computeEdgeSharpness(imageData: ImageData) -> Float {
        var gradientSum: Float = 0
        var gradientCount = 0

        let width = imageData.width
        let height = imageData.height

        // Sample gradient at regular intervals for efficiency
        let step = max(1, min(width, height) / 100)

        for y in stride(from: 1, to: height - 1, by: step) {
            for x in stride(from: 1, to: width - 1, by: step) {
                // Get grayscale values in 3x3 neighborhood
                let idx = { (px: Int, py: Int) -> Int in (py * width + px) * 4 }

                let grayAt = { (px: Int, py: Int) -> Float in
                    let i = idx(px, py)
                    return (Float(imageData.rgba[i]) + Float(imageData.rgba[i + 1]) + Float(imageData.rgba[i + 2])) / (3.0 * 255.0)
                }

                // Sobel gradient approximation
                let gx = -grayAt(x - 1, y - 1) - 2 * grayAt(x - 1, y) - grayAt(x - 1, y + 1) +
                          grayAt(x + 1, y - 1) + 2 * grayAt(x + 1, y) + grayAt(x + 1, y + 1)

                let gy = -grayAt(x - 1, y - 1) - 2 * grayAt(x, y - 1) - grayAt(x + 1, y - 1) +
                          grayAt(x - 1, y + 1) + 2 * grayAt(x, y + 1) + grayAt(x + 1, y + 1)

                let magnitude = sqrt(gx * gx + gy * gy)
                gradientSum += magnitude
                gradientCount += 1
            }
        }

        guard gradientCount > 0 else { return 0 }

        // Normalize to 0-1 range (max gradient magnitude is ~2.83)
        let avgGradient = gradientSum / Float(gradientCount)
        return min(1.0, avgGradient / 1.0)
    }

    /// Computes periodicity score by analyzing autocorrelation.
    /// Higher values indicate regular periodic patterns (screen pixels).
    private func computePeriodicity(imageData: ImageData) -> Float {
        let width = imageData.width
        let height = imageData.height

        // Convert to grayscale row for horizontal periodicity analysis
        let rowY = height / 2
        var rowData = [Float](repeating: 0, count: width)

        for x in 0..<width {
            let i = (rowY * width + x) * 4
            rowData[x] = (Float(imageData.rgba[i]) + Float(imageData.rgba[i + 1]) + Float(imageData.rgba[i + 2])) / (3.0 * 255.0)
        }

        // Compute autocorrelation for small lags (screen pixel spacing)
        var autocorrSum: Float = 0
        var autocorrCount = 0

        // Mean subtraction
        let mean = rowData.reduce(0, +) / Float(width)
        let centered = rowData.map { $0 - mean }

        // Variance
        let variance = centered.map { $0 * $0 }.reduce(0, +) / Float(width)
        guard variance > 0.0001 else { return 0 } // Uniform row

        // Check small lags (3-10 pixels typical for screen pixels)
        for lag in 3...10 {
            guard lag < width else { break }

            var correlation: Float = 0
            for i in 0..<(width - lag) {
                correlation += centered[i] * centered[i + lag]
            }
            correlation /= Float(width - lag) * variance

            if correlation > 0.3 { // Strong periodic correlation
                autocorrSum += correlation
                autocorrCount += 1
            }
        }

        // Normalize: if we found multiple strong periodic correlations, it's periodic
        return autocorrCount > 0 ? min(1.0, autocorrSum / Float(autocorrCount)) : 0
    }

    /// Computes high frequency content ratio.
    /// Real scenes have more natural high-frequency detail.
    private func computeHighFrequencyContent(imageData: ImageData) -> Float {
        let width = imageData.width
        let height = imageData.height

        var highFreqSum: Float = 0
        var totalSum: Float = 0
        var sampleCount = 0

        // Laplacian-like high frequency detection
        let step = max(1, min(width, height) / 50)

        for y in stride(from: 1, to: height - 1, by: step) {
            for x in stride(from: 1, to: width - 1, by: step) {
                let idx = { (px: Int, py: Int) -> Int in (py * width + px) * 4 }

                let grayAt = { (px: Int, py: Int) -> Float in
                    let i = idx(px, py)
                    return (Float(imageData.rgba[i]) + Float(imageData.rgba[i + 1]) + Float(imageData.rgba[i + 2])) / (3.0 * 255.0)
                }

                let center = grayAt(x, y)
                let laplacian = abs(-4 * center +
                                   grayAt(x - 1, y) + grayAt(x + 1, y) +
                                   grayAt(x, y - 1) + grayAt(x, y + 1))

                highFreqSum += laplacian
                totalSum += abs(center)
                sampleCount += 1
            }
        }

        guard sampleCount > 0 && totalSum > 0 else { return 0 }

        // Ratio of high frequency to total content
        return min(1.0, (highFreqSum / Float(sampleCount)) * 4.0)
    }

    /// Computes color uniformity (how similar are colors across the image).
    /// Screens tend to have more uniform color distributions.
    private func computeColorUniformity(imageData: ImageData) -> Float {
        // Sample pixels and compute color histogram spread
        var rHist = [Int](repeating: 0, count: 32)
        var gHist = [Int](repeating: 0, count: 32)
        var bHist = [Int](repeating: 0, count: 32)

        let step = max(1, imageData.pixelCount / 1000)

        for i in stride(from: 0, to: imageData.rgba.count, by: step * 4) {
            let r = Int(imageData.rgba[i]) / 8
            let g = Int(imageData.rgba[i + 1]) / 8
            let b = Int(imageData.rgba[i + 2]) / 8

            rHist[r] += 1
            gHist[g] += 1
            bHist[b] += 1
        }

        // Compute entropy of each channel
        let entropy = { (hist: [Int]) -> Float in
            let total = Float(hist.reduce(0, +))
            guard total > 0 else { return 0 }

            var e: Float = 0
            for count in hist {
                if count > 0 {
                    let p = Float(count) / total
                    e -= p * log2(p)
                }
            }
            return e / log2(32) // Normalize to 0-1
        }

        let avgEntropy = (entropy(rHist) + entropy(gHist) + entropy(bHist)) / 3.0

        // Lower entropy = more uniform = higher uniformity score
        return max(0, 1.0 - avgEntropy)
    }

    // MARK: - Score Computation

    /// Computes score for real scene classification.
    private func computeRealSceneScore(
        colorVariance: Float,
        edgeSharpness: Float,
        periodicity: Float,
        highFreqContent: Float,
        colorUniformity: Float
    ) -> Float {
        // Real scenes: high variance, natural edges, low periodicity, varied colors
        var score: Float = 0

        // High color variance is good
        score += colorVariance * 0.25

        // Moderate edge sharpness (not too sharp, not too soft)
        let edgeScore = 1.0 - abs(edgeSharpness - 0.5) * 2.0
        score += edgeScore * 0.15

        // Low periodicity is good
        score += (1.0 - periodicity) * 0.25

        // High frequency content is good
        score += highFreqContent * 0.20

        // Low uniformity (varied colors) is good
        score += (1.0 - colorUniformity) * 0.15

        return min(1.0, max(0, score))
    }

    /// Computes score for LCD screen classification.
    private func computeLCDScreenScore(
        colorVariance: Float,
        edgeSharpness: Float,
        periodicity: Float,
        colorUniformity: Float
    ) -> Float {
        // LCD: uniform colors, high periodicity, sharp edges
        var score: Float = 0

        // Low color variance
        score += (1.0 - colorVariance) * 0.20

        // Sharp edges (pixel boundaries)
        score += edgeSharpness * 0.25

        // High periodicity (pixel grid)
        score += periodicity * 0.35

        // High uniformity
        score += colorUniformity * 0.20

        return min(1.0, max(0, score))
    }

    /// Computes score for OLED screen classification.
    /// Similar to LCD but with different periodicity patterns.
    private func computeOLEDScreenScore(
        colorVariance: Float,
        edgeSharpness: Float,
        periodicity: Float,
        colorUniformity: Float
    ) -> Float {
        // OLED: similar to LCD but slightly different characteristics
        // Pentile pattern may show different periodicity
        var score: Float = 0

        // Low-moderate color variance (true blacks create more variance)
        score += (1.0 - colorVariance * 0.8) * 0.15

        // Sharp edges
        score += edgeSharpness * 0.20

        // Moderate-high periodicity (pentile is less regular than LCD)
        score += periodicity * 0.25

        // Moderate uniformity
        score += colorUniformity * 0.15

        // OLED is harder to detect, lower base score
        return min(1.0, max(0, score * 0.85))
    }

    /// Computes score for printed paper classification.
    private func computePrintedPaperScore(
        colorVariance: Float,
        edgeSharpness: Float,
        periodicity: Float,
        highFreqContent: Float,
        colorUniformity: Float
    ) -> Float {
        // Prints: soft edges, halftone patterns, limited colors
        var score: Float = 0

        // Moderate-low color variance (limited printer gamut)
        let varianceScore = colorVariance < 0.5 ? (0.5 - colorVariance) * 2.0 : 0
        score += varianceScore * 0.15

        // Soft edges (ink spread)
        score += (1.0 - edgeSharpness) * 0.25

        // Some periodicity (halftone dots)
        let halftonePeriodicity = periodicity > 0.1 && periodicity < 0.5 ? periodicity : 0
        score += halftonePeriodicity * 0.20

        // Low high-frequency content (lost in printing)
        score += (1.0 - highFreqContent) * 0.20

        // Moderate uniformity
        let uniformityScore: Float = colorUniformity > 0.3 && colorUniformity < 0.7 ? 0.5 : 0
        score += uniformityScore * 0.20

        return min(1.0, max(0, score))
    }

    /// Determines final classification from scores.
    private func determineClassification(scores: [TextureType: Float]) -> (TextureType, Float) {
        var bestType: TextureType = .unknown
        var bestScore: Float = 0

        for (type, score) in scores {
            if score > bestScore {
                bestScore = score
                bestType = type
            }
        }

        // If best score is too low, return unknown
        if bestScore < TextureClassificationConstants.minClassificationConfidence {
            return (.unknown, bestScore)
        }

        return (bestType, bestScore)
    }
}
