//
//  MoireDetectionService.swift
//  Rial
//
//  Created by RealityCam on 2025-12-11.
//
//  Moire pattern detection service using 2D FFT (Story 9-1).
//  Detects screen pixel grid interference patterns via frequency analysis.
//

import Foundation
import CoreGraphics
import CoreVideo
import Accelerate
import os.log

// MARK: - MoireDetectionService

/// Service for detecting moire patterns in captured images via 2D FFT analysis.
///
/// ## Algorithm Overview
/// Moire patterns appear when photographing screens due to interference between
/// the camera sensor grid and screen pixel grid. These create characteristic
/// periodic artifacts detectable in the frequency domain.
///
/// The analysis pipeline:
/// 1. Convert image to grayscale float array
/// 2. Pad to power-of-2 dimensions with Hanning window
/// 3. Perform 2D FFT using vDSP (Accelerate framework)
/// 4. Compute magnitude spectrum
/// 5. Detect periodic peaks in moire frequency range (50-300 cycles/width)
/// 6. Classify screen type based on peak patterns
/// 7. Compute detection confidence
///
/// ## Performance
/// - Target: 30ms on iPhone 12 Pro+
/// - Acceptable: <100ms
/// - Memory: <100MB during analysis
///
/// ## Security Note
/// Per PRD research, moire detection alone is vulnerable to Chimera attacks.
/// This is a SUPPORTING signal (15% weight), not PRIMARY (LiDAR is primary).
/// Always cross-validate with other detection methods.
///
/// ## Usage
/// ```swift
/// let result = await MoireDetectionService.shared.analyze(image: cgImage)
/// if result.detected && result.confidence > 0.5 {
///     // Likely screen recapture
/// }
/// ```
///
/// ## Thread Safety
/// This class is marked `@unchecked Sendable` because:
/// 1. All mutable state (`cachedFFTSetup`, `cachedLog2n`) is protected by `fftSetupQueue`
/// 2. The serial queue ensures atomic read-modify-write operations
/// 3. Public API uses async/await with work dispatched to background queues
/// An actor-based design was considered but would add overhead for this compute-bound service.
public final class MoireDetectionService: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared singleton instance
    public static let shared = MoireDetectionService()

    // MARK: - Properties

    /// Logger for moire detection events
    private static let logger = Logger(subsystem: "app.rial", category: "moiredetection")

    /// Signpost log for performance tracking
    private static let signpostLog = OSLog(subsystem: "app.rial", category: .pointsOfInterest)

    /// Cached FFT setup for reuse (significant performance gain)
    /// Protected by `fftSetupQueue` for thread safety
    private var cachedFFTSetup: FFTSetup?
    private var cachedLog2n: vDSP_Length = 0

    /// Serial queue for FFT setup access
    private let fftSetupQueue = DispatchQueue(label: "app.rial.moiredetection.fftsetup")

    // MARK: - Initialization

    /// Private initializer for singleton pattern
    private init() {
        Self.logger.debug("MoireDetectionService initialized")
    }

    deinit {
        // Clean up cached FFT setup
        if let setup = cachedFFTSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    // MARK: - Public API

    /// Analyzes a CGImage for moire patterns.
    ///
    /// - Parameter image: CGImage to analyze
    /// - Returns: MoireAnalysisResult with detection results
    public func analyze(image: CGImage) async -> MoireAnalysisResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performAnalysis(image: image)
                continuation.resume(returning: result)
            }
        }
    }

    /// Analyzes a CVPixelBuffer for moire patterns.
    ///
    /// - Parameter pixelBuffer: CVPixelBuffer to analyze (RGB, BGRA, or grayscale)
    /// - Returns: MoireAnalysisResult with detection results
    public func analyze(pixelBuffer: CVPixelBuffer) async -> MoireAnalysisResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performAnalysis(pixelBuffer: pixelBuffer)
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Internal Analysis

    /// Performs moire analysis on a CGImage.
    private func performAnalysis(image: CGImage) -> MoireAnalysisResult {
        let signpostID = OSSignpostID(log: Self.signpostLog)
        os_signpost(.begin, log: Self.signpostLog, name: "MoireAnalysis", signpostID: signpostID)
        defer {
            os_signpost(.end, log: Self.signpostLog, name: "MoireAnalysis", signpostID: signpostID)
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Validate image dimensions
        let width = image.width
        let height = image.height

        guard width >= MoireAnalysisConstants.minImageDimension,
              height >= MoireAnalysisConstants.minImageDimension else {
            Self.logger.error("Image too small: \(width)x\(height)")
            return .unavailable()
        }

        Self.logger.debug("Analyzing image: \(width)x\(height)")

        // Convert to grayscale float array
        guard let grayscale = convertToGrayscale(image: image) else {
            Self.logger.error("Failed to convert image to grayscale")
            return .unavailable()
        }

        // Continue with common analysis pipeline
        return analyzeGrayscale(
            grayscale: grayscale,
            originalWidth: width,
            originalHeight: height,
            startTime: startTime
        )
    }

    /// Performs moire analysis on a CVPixelBuffer.
    private func performAnalysis(pixelBuffer: CVPixelBuffer) -> MoireAnalysisResult {
        let signpostID = OSSignpostID(log: Self.signpostLog)
        os_signpost(.begin, log: Self.signpostLog, name: "MoireAnalysis", signpostID: signpostID)
        defer {
            os_signpost(.end, log: Self.signpostLog, name: "MoireAnalysis", signpostID: signpostID)
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard width >= MoireAnalysisConstants.minImageDimension,
              height >= MoireAnalysisConstants.minImageDimension else {
            Self.logger.error("Image too small: \(width)x\(height)")
            return .unavailable()
        }

        Self.logger.debug("Analyzing pixel buffer: \(width)x\(height)")

        // Convert to grayscale float array
        guard let grayscale = convertToGrayscale(pixelBuffer: pixelBuffer) else {
            Self.logger.error("Failed to convert pixel buffer to grayscale")
            return .unavailable()
        }

        return analyzeGrayscale(
            grayscale: grayscale,
            originalWidth: width,
            originalHeight: height,
            startTime: startTime
        )
    }

    /// Common analysis pipeline for grayscale data.
    private func analyzeGrayscale(
        grayscale: GrayscaleImage,
        originalWidth: Int,
        originalHeight: Int,
        startTime: CFAbsoluteTime
    ) -> MoireAnalysisResult {

        // Determine FFT size (power of 2)
        let fftSize = computeFFTSize(width: grayscale.width, height: grayscale.height)

        Self.logger.debug("Using FFT size: \(fftSize)x\(fftSize)")

        // Pad and window the image
        guard let paddedData = padAndWindow(
            grayscale: grayscale,
            targetSize: fftSize
        ) else {
            Self.logger.error("Failed to pad image for FFT")
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            return .failed(analysisTimeMs: elapsed)
        }

        // Perform 2D FFT
        guard let magnitudeSpectrum = perform2DFFT(data: paddedData, size: fftSize) else {
            Self.logger.error("Failed to perform 2D FFT")
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            return .failed(analysisTimeMs: elapsed)
        }

        // Detect frequency peaks
        let peaks = detectPeaks(
            spectrum: magnitudeSpectrum,
            size: fftSize,
            originalWidth: originalWidth
        )

        // Classify screen type
        let screenType = classifyScreenType(peaks: peaks)

        // Compute confidence
        let (detected, confidence) = computeConfidence(peaks: peaks, screenType: screenType)

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let elapsedMs = Int(elapsed * 1000)

        Self.logger.info("""
            Moire analysis complete in \(elapsedMs)ms:
            detected=\(detected),
            confidence=\(String(format: "%.3f", confidence)),
            peaks=\(peaks.count),
            screenType=\(screenType?.rawValue ?? "nil")
            """)

        if elapsedMs > MoireAnalysisConstants.maxTimeMs {
            Self.logger.warning("Moire analysis exceeded \(MoireAnalysisConstants.maxTimeMs)ms target: \(elapsedMs)ms")
        }

        return MoireAnalysisResult(
            detected: detected,
            confidence: confidence,
            peaks: peaks,
            screenType: screenType,
            analysisTimeMs: elapsedMs
        )
    }

    // MARK: - Grayscale Conversion

    /// Holds grayscale image data
    private struct GrayscaleImage {
        let data: [Float]
        let width: Int
        let height: Int
    }

    /// Converts CGImage to grayscale float array.
    private func convertToGrayscale(image: CGImage) -> GrayscaleImage? {
        let width = image.width
        let height = image.height

        // Downsample if too large
        let targetWidth: Int
        let targetHeight: Int
        if width > MoireAnalysisConstants.maxImageDimension ||
           height > MoireAnalysisConstants.maxImageDimension {
            let scale = Float(MoireAnalysisConstants.targetFFTSize) / Float(max(width, height))
            targetWidth = Int(Float(width) * scale)
            targetHeight = Int(Float(height) * scale)
        } else {
            targetWidth = width
            targetHeight = height
        }

        // Create grayscale context
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            Self.logger.error("Failed to create grayscale context")
            return nil
        }

        // Draw image to grayscale context
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        guard let data = context.data else {
            Self.logger.error("Failed to get context data")
            return nil
        }

        // Convert UInt8 to Float [0.0-1.0]
        let pixelCount = targetWidth * targetHeight
        let bytePointer = data.bindMemory(to: UInt8.self, capacity: pixelCount)
        var floatData = [Float](repeating: 0, count: pixelCount)

        // Use vDSP for efficient conversion
        var source = [Float](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            source[i] = Float(bytePointer[i])
        }

        // Normalize to 0-1 range
        var divisor: Float = 255.0
        vDSP_vsdiv(source, 1, &divisor, &floatData, 1, vDSP_Length(pixelCount))

        return GrayscaleImage(data: floatData, width: targetWidth, height: targetHeight)
    }

    /// Converts CVPixelBuffer to grayscale float array.
    private func convertToGrayscale(pixelBuffer: CVPixelBuffer) -> GrayscaleImage? {
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

        // Determine pixel format and convert
        let pixelCount = width * height
        var grayscale = [Float](repeating: 0, count: pixelCount)

        switch pixelFormat {
        case kCVPixelFormatType_32BGRA, kCVPixelFormatType_32RGBA:
            // 4-byte RGBA/BGRA format
            let bytesPerPixel = 4
            let data = baseAddress.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)

            for y in 0..<height {
                for x in 0..<width {
                    let srcOffset = y * bytesPerRow + x * bytesPerPixel
                    let dstOffset = y * width + x

                    // ITU-R BT.601 luma coefficients
                    let r: Float
                    let g: Float
                    let b: Float

                    if pixelFormat == kCVPixelFormatType_32BGRA {
                        b = Float(data[srcOffset])
                        g = Float(data[srcOffset + 1])
                        r = Float(data[srcOffset + 2])
                    } else {
                        r = Float(data[srcOffset])
                        g = Float(data[srcOffset + 1])
                        b = Float(data[srcOffset + 2])
                    }

                    grayscale[dstOffset] = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                }
            }

        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            // YCbCr format - use Y plane directly
            guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
                Self.logger.error("Failed to get Y plane")
                return nil
            }
            let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let yData = yPlane.bindMemory(to: UInt8.self, capacity: height * yBytesPerRow)

            for y in 0..<height {
                for x in 0..<width {
                    let srcOffset = y * yBytesPerRow + x
                    let dstOffset = y * width + x
                    grayscale[dstOffset] = Float(yData[srcOffset]) / 255.0
                }
            }

        default:
            Self.logger.error("Unsupported pixel format: \(pixelFormat)")
            return nil
        }

        // Downsample if needed
        if width > MoireAnalysisConstants.maxImageDimension ||
           height > MoireAnalysisConstants.maxImageDimension {
            return downsampleGrayscale(
                GrayscaleImage(data: grayscale, width: width, height: height)
            )
        }

        return GrayscaleImage(data: grayscale, width: width, height: height)
    }

    /// Downsamples grayscale image to target FFT size.
    private func downsampleGrayscale(_ image: GrayscaleImage) -> GrayscaleImage? {
        let scale = Float(MoireAnalysisConstants.targetFFTSize) / Float(max(image.width, image.height))
        let newWidth = max(MoireAnalysisConstants.minImageDimension, Int(Float(image.width) * scale))
        let newHeight = max(MoireAnalysisConstants.minImageDimension, Int(Float(image.height) * scale))

        var result = [Float](repeating: 0, count: newWidth * newHeight)

        let scaleX = Float(image.width) / Float(newWidth)
        let scaleY = Float(image.height) / Float(newHeight)

        for y in 0..<newHeight {
            for x in 0..<newWidth {
                let srcX = Int(Float(x) * scaleX)
                let srcY = Int(Float(y) * scaleY)
                let srcIdx = srcY * image.width + srcX
                result[y * newWidth + x] = image.data[srcIdx]
            }
        }

        return GrayscaleImage(data: result, width: newWidth, height: newHeight)
    }

    // MARK: - FFT Processing

    /// Computes optimal FFT size (power of 2).
    private func computeFFTSize(width: Int, height: Int) -> Int {
        let maxDim = max(width, height)
        let targetSize = min(maxDim, MoireAnalysisConstants.targetFFTSize)

        // Find next power of 2
        var size = 64
        while size < targetSize {
            size *= 2
        }
        return size
    }

    /// Pads image to FFT size and applies Hanning window to reduce spectral leakage.
    private func padAndWindow(grayscale: GrayscaleImage, targetSize: Int) -> [Float]? {
        var padded = [Float](repeating: 0, count: targetSize * targetSize)

        // Center the image in padded buffer
        let offsetX = (targetSize - grayscale.width) / 2
        let offsetY = (targetSize - grayscale.height) / 2

        // Create 2D Hanning window
        var hanningH = [Float](repeating: 0, count: grayscale.height)
        var hanningW = [Float](repeating: 0, count: grayscale.width)
        vDSP_hann_window(&hanningH, vDSP_Length(grayscale.height), Int32(vDSP_HANN_NORM))
        vDSP_hann_window(&hanningW, vDSP_Length(grayscale.width), Int32(vDSP_HANN_NORM))

        // Copy image data with windowing
        for y in 0..<grayscale.height {
            for x in 0..<grayscale.width {
                let srcIdx = y * grayscale.width + x
                let dstIdx = (y + offsetY) * targetSize + (x + offsetX)
                let window = hanningH[y] * hanningW[x]
                padded[dstIdx] = grayscale.data[srcIdx] * window
            }
        }

        // Subtract mean to center DC component
        var mean: Float = 0
        vDSP_meanv(padded, 1, &mean, vDSP_Length(padded.count))
        var negMean = -mean
        vDSP_vsadd(padded, 1, &negMean, &padded, 1, vDSP_Length(padded.count))

        return padded
    }

    /// Performs 2D FFT and returns magnitude spectrum.
    private func perform2DFFT(data: [Float], size: Int) -> [Float]? {
        let log2n = vDSP_Length(log2(Float(size)))

        // Get or create FFT setup (cached for performance)
        // Handles low-memory conditions gracefully by returning nil
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
                Self.logger.error("Failed to create FFT setup - low memory condition")
                return nil
            }

            cachedFFTSetup = newSetup
            cachedLog2n = log2n
            return newSetup
        }

        guard let fftSetup = maybeFFTSetup else {
            Self.logger.error("FFT setup unavailable, cannot perform analysis")
            return nil
        }

        let count = size * size

        // Prepare split complex data
        var realp = [Float](repeating: 0, count: count)
        var imagp = [Float](repeating: 0, count: count)

        // Copy input data to real part
        realp = data

        // Compute magnitude spectrum: sqrt(real^2 + imag^2)
        var magnitudes = [Float](repeating: 0, count: count)

        // Perform FFT using proper buffer management
        realp.withUnsafeMutableBufferPointer { realBuf in
            imagp.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)

                // Perform 2D FFT
                vDSP_fft2d_zip(
                    fftSetup,
                    &split,
                    1,
                    0,
                    log2n,
                    log2n,
                    FFTDirection(FFT_FORWARD)
                )

                // Compute squared magnitudes
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(count))
            }
        }

        // Take square root for actual magnitude
        var sqrtMagnitudes = [Float](repeating: 0, count: count)
        var countVal = Int32(count)
        vvsqrtf(&sqrtMagnitudes, magnitudes, &countVal)

        // Apply log scaling for better visualization and peak detection
        // log(1 + magnitude) to avoid log(0)
        var one: Float = 1.0
        vDSP_vsadd(sqrtMagnitudes, 1, &one, &sqrtMagnitudes, 1, vDSP_Length(count))
        vvlog10f(&magnitudes, sqrtMagnitudes, &countVal)

        // Normalize to 0-1 range
        var maxMag: Float = 0
        vDSP_maxv(magnitudes, 1, &maxMag, vDSP_Length(count))
        if maxMag > 0 {
            vDSP_vsdiv(magnitudes, 1, &maxMag, &magnitudes, 1, vDSP_Length(count))
        }

        // Shift FFT to center (DC at center)
        return fftShift(magnitudes, size: size)
    }

    /// Shifts FFT output so DC component is at center.
    private func fftShift(_ data: [Float], size: Int) -> [Float] {
        var shifted = [Float](repeating: 0, count: size * size)
        let half = size / 2

        for y in 0..<size {
            for x in 0..<size {
                let srcX = (x + half) % size
                let srcY = (y + half) % size
                shifted[y * size + x] = data[srcY * size + srcX]
            }
        }

        return shifted
    }

    // MARK: - Peak Detection

    /// Detects frequency peaks in the magnitude spectrum.
    private func detectPeaks(spectrum: [Float], size: Int, originalWidth: Int) -> [FrequencyPeak] {
        var peaks = [FrequencyPeak]()

        // Compute noise floor (median of non-DC region)
        let center = size / 2
        var nonDCValues = [Float]()

        for y in 0..<size {
            for x in 0..<size {
                let dx = x - center
                let dy = y - center
                let dist = sqrt(Float(dx * dx + dy * dy))

                // Skip DC and very low frequencies
                if dist > 5 && dist < Float(size / 2) {
                    nonDCValues.append(spectrum[y * size + x])
                }
            }
        }

        guard !nonDCValues.isEmpty else {
            return []
        }

        nonDCValues.sort()
        let medianMag = nonDCValues[nonDCValues.count / 2]
        let noiseThreshold = medianMag * MoireAnalysisConstants.noiseFloorMultiplier

        Self.logger.debug("Noise threshold: \(String(format: "%.4f", noiseThreshold))")

        // Frequency scaling: pixels in FFT to cycles per image width
        let freqScale = Float(originalWidth) / Float(size)

        // Search for local maxima in moire frequency range
        let minFreqPx = Int(MoireAnalysisConstants.minFrequency / freqScale)
        let maxFreqPx = Int(MoireAnalysisConstants.maxFrequency / freqScale)

        for y in 2..<(size - 2) {
            for x in 2..<(size - 2) {
                let dx = x - center
                let dy = y - center
                let distPx = sqrt(Float(dx * dx + dy * dy))

                // Check if in moire frequency range
                guard Int(distPx) >= minFreqPx && Int(distPx) <= maxFreqPx else {
                    continue
                }

                let idx = y * size + x
                let mag = spectrum[idx]

                // Check if above noise threshold AND minimum absolute magnitude
                // This prevents detecting numerical artifacts in low-energy (uniform) images
                guard mag > noiseThreshold && mag >= MoireAnalysisConstants.minPeakMagnitude else {
                    continue
                }

                // Check if local maximum (3x3 neighborhood)
                var isMax = true
                for ny in -2...2 {
                    for nx in -2...2 {
                        if nx == 0 && ny == 0 { continue }
                        let neighborIdx = (y + ny) * size + (x + nx)
                        if spectrum[neighborIdx] >= mag {
                            isMax = false
                            break
                        }
                    }
                    if !isMax { break }
                }

                guard isMax else { continue }

                // Compute peak prominence (ratio to local average)
                var localSum: Float = 0
                var localCount = 0
                let windowSize = 5

                for wy in -windowSize...windowSize {
                    for wx in -windowSize...windowSize {
                        if abs(wx) <= 1 && abs(wy) <= 1 { continue } // Exclude center region
                        let neighborIdx = (y + wy) * size + (x + wx)
                        if neighborIdx >= 0 && neighborIdx < size * size {
                            localSum += spectrum[neighborIdx]
                            localCount += 1
                        }
                    }
                }

                let localAvg = localCount > 0 ? localSum / Float(localCount) : medianMag
                let prominence = localAvg > 0 ? mag / localAvg : 0

                // Filter by prominence
                guard prominence >= MoireAnalysisConstants.minPeakProminence else {
                    continue
                }

                // Compute frequency and angle
                let frequency = distPx * freqScale
                let angle = atan2(Float(dy), Float(dx))

                let peak = FrequencyPeak(
                    frequency: frequency,
                    magnitude: mag,
                    angle: angle,
                    prominence: prominence
                )

                peaks.append(peak)
            }
        }

        // Sort by magnitude and limit count
        peaks.sort { $0.magnitude > $1.magnitude }
        if peaks.count > MoireAnalysisConstants.maxPeaksToReport {
            peaks = Array(peaks.prefix(MoireAnalysisConstants.maxPeaksToReport))
        }

        Self.logger.debug("Detected \(peaks.count) frequency peaks")

        return peaks
    }

    // MARK: - Screen Classification

    /// Classifies screen type based on peak patterns.
    private func classifyScreenType(peaks: [FrequencyPeak]) -> ScreenType? {
        guard peaks.count >= MoireAnalysisConstants.minPeaksForDetection else {
            return nil
        }

        // Look for characteristic patterns

        // Check for orthogonal peak pairs (horizontal + vertical grid)
        var hasHorizontal = false
        var hasVertical = false

        for peak in peaks {
            let angleMod = abs(peak.angle).truncatingRemainder(dividingBy: Float.pi)

            // Horizontal peaks (angle near 0 or pi)
            if angleMod < MoireAnalysisConstants.angleTolerance ||
               abs(angleMod - Float.pi) < MoireAnalysisConstants.angleTolerance {
                hasHorizontal = true
            }

            // Vertical peaks (angle near pi/2)
            if abs(angleMod - Float.pi / 2) < MoireAnalysisConstants.angleTolerance {
                hasVertical = true
            }
        }

        // Need both directions for screen grid pattern
        guard hasHorizontal && hasVertical else {
            return peaks.count >= 2 ? .unknown : nil
        }

        // Check frequency ratios to distinguish LCD vs OLED
        // Group peaks by similar frequency
        let sortedPeaks = peaks.sorted { $0.frequency < $1.frequency }

        if sortedPeaks.count >= 2 {
            let freqRatio = sortedPeaks[1].frequency / sortedPeaks[0].frequency

            // LCD: 1:1 ratio (regular RGB stripe)
            if abs(freqRatio - MoireAnalysisConstants.lcdFrequencyRatio) <
                MoireAnalysisConstants.frequencyRatioTolerance {
                return .lcd
            }

            // OLED: sqrt(2) ratio (pentile diamond)
            if abs(freqRatio - MoireAnalysisConstants.oledFrequencyRatio) <
                MoireAnalysisConstants.frequencyRatioTolerance {
                return .oled
            }
        }

        // Check for high refresh rate indicators (multiple harmonics)
        var harmonicCount = 0
        if let fundamentalFreq = sortedPeaks.first?.frequency {
            for peak in sortedPeaks.dropFirst() {
                let ratio = peak.frequency / fundamentalFreq
                let roundedRatio = round(ratio)
                if abs(ratio - roundedRatio) < 0.1 && roundedRatio >= 2 {
                    harmonicCount += 1
                }
            }
        }

        if harmonicCount >= 2 {
            return .highRefresh
        }

        return .unknown
    }

    // MARK: - Confidence Computation

    /// Computes detection confidence based on peak analysis.
    private func computeConfidence(peaks: [FrequencyPeak], screenType: ScreenType?) -> (detected: Bool, confidence: Float) {
        guard !peaks.isEmpty else {
            return (false, 0)
        }

        var confidence: Float = 0

        // Base confidence from peak count and strength
        let peakCount = min(peaks.count, 5) // Cap contribution
        confidence += Float(peakCount) * 0.1

        // Boost from peak prominences
        let avgProminence = peaks.reduce(0) { $0 + $1.prominence } / Float(peaks.count)
        confidence += min(avgProminence / 10.0, 0.3)

        // Boost from strongest peak magnitude
        if let maxMag = peaks.first?.magnitude {
            confidence += maxMag * 0.2
        }

        // Boost if screen type identified
        if screenType != nil && screenType != .unknown {
            confidence += MoireAnalysisConstants.screenPatternBoost
        }

        // Penalty for unknown type when peaks present
        if screenType == .unknown && peaks.count >= 2 {
            confidence -= MoireAnalysisConstants.ambiguousPenalty * 0.5
        }

        // Clamp to 0-1 range
        confidence = max(0, min(1, confidence))

        // Determine detection
        let detected = confidence >= MoireAnalysisConstants.minDetectionConfidence &&
                       peaks.count >= MoireAnalysisConstants.minPeaksForDetection

        return (detected, confidence)
    }
}
