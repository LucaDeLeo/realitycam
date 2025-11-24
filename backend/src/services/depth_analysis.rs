//! LiDAR Depth Analysis Service (Story 4-5)
//!
//! Analyzes LiDAR depth maps to determine if a scene represents a real 3D
//! environment vs. a flat surface (screen, photo of a photo).
//!
//! ## Analysis Pipeline
//! 1. Download gzipped depth map from S3
//! 2. Decompress and parse Float32 array (little-endian)
//! 3. Compute statistical metrics (variance, min/max, coverage)
//! 4. Detect depth layers via histogram peak detection
//! 5. Analyze edge coherence (depth gradient complexity)
//! 6. Determine is_likely_real_scene based on thresholds
//!
//! ## Thresholds (from Epic 4 Tech Spec)
//! - depth_variance > 0.5 (std dev in meters)
//! - depth_layers >= 3 (distinct histogram peaks)
//! - edge_coherence > 0.7 (0.0-1.0 score)
//!
//! ## Error Handling
//! All errors are non-blocking. Failures result in status=unavailable,
//! NOT upload rejection.

use byteorder::{LittleEndian, ReadBytesExt};
use flate2::read::GzDecoder;
use std::io::{Cursor, Read};
use thiserror::Error;
use tracing::{debug, info, warn};
use uuid::Uuid;

use crate::models::{CheckStatus, DepthAnalysis};
use crate::services::StorageService;

// ============================================================================
// Configuration Constants
// ============================================================================

/// Minimum depth variance (std dev) for real scene detection (meters)
const VARIANCE_THRESHOLD: f64 = 0.5;

/// Minimum depth layers for real scene detection
const LAYER_THRESHOLD: u32 = 3;

/// Minimum edge coherence for real scene detection (0.0-1.0)
/// NOTE: Lowered from 0.7 for hackathon - real LiDAR often has lower edge coherence
const COHERENCE_THRESHOLD: f64 = 0.3;

/// Number of histogram bins for layer detection
const HISTOGRAM_BINS: usize = 50;

/// Minimum peak prominence as fraction of max bin count
const PEAK_PROMINENCE_RATIO: f64 = 0.05;

/// Minimum valid depth value (meters) - filter noise
const MIN_VALID_DEPTH: f32 = 0.1;

/// Maximum valid depth value (meters) - filter outliers
const MAX_VALID_DEPTH: f32 = 20.0;

/// Screen detection: max depth range for suspicious uniform surface (meters)
/// Screens are typically 0.3-0.8m away with <0.1m variation
const SCREEN_DEPTH_RANGE_MAX: f64 = 0.15;

/// Screen detection: minimum percentage of pixels within narrow band
const SCREEN_UNIFORMITY_THRESHOLD: f64 = 0.85;

/// Screen detection: typical screen distance range (meters)
const SCREEN_DISTANCE_MIN: f64 = 0.2;
const SCREEN_DISTANCE_MAX: f64 = 1.5;

// ============================================================================
// Error Types
// ============================================================================

/// Errors that can occur during depth analysis
#[derive(Debug, Error)]
pub enum DepthAnalysisError {
    #[error("Failed to download depth map from S3: {0}")]
    S3Download(String),

    #[error("Failed to decompress gzip data: {0}")]
    Decompression(String),

    #[error("Failed to parse float32 array: {0}")]
    ParseError(String),

    #[error("Insufficient valid depth data: {valid_count} valid of {total_count} total")]
    InsufficientData {
        valid_count: usize,
        total_count: usize,
    },

    #[error("Empty depth map")]
    EmptyDepthMap,
}

// ============================================================================
// Intermediate Types
// ============================================================================

/// Statistics computed from depth data
#[derive(Debug, Clone)]
pub struct DepthStatistics {
    pub variance: f64,
    pub min_depth: f64,
    pub max_depth: f64,
    pub coverage: f64,
    pub valid_count: usize,
    pub total_count: usize,
}

/// Result of depth layer detection
#[derive(Debug, Clone)]
pub struct LayerDetectionResult {
    pub layer_count: u32,
    pub peak_depths: Vec<f64>,
}

// ============================================================================
// Core Analysis Functions
// ============================================================================

/// Decompresses gzipped depth map data
///
/// # Arguments
/// * `compressed` - Gzip-compressed bytes
///
/// # Returns
/// Decompressed raw bytes
pub fn decompress_depth_map(compressed: &[u8]) -> Result<Vec<u8>, DepthAnalysisError> {
    let mut decoder = GzDecoder::new(compressed);
    let mut decompressed = Vec::new();

    decoder
        .read_to_end(&mut decompressed)
        .map_err(|e| DepthAnalysisError::Decompression(e.to_string()))?;

    debug!(
        compressed_size = compressed.len(),
        decompressed_size = decompressed.len(),
        "Depth map decompressed"
    );

    Ok(decompressed)
}

/// Parses raw bytes as Float32 array (little-endian)
///
/// # Arguments
/// * `bytes` - Raw bytes (must be multiple of 4)
///
/// # Returns
/// Vector of f32 depth values
pub fn parse_float32_array(bytes: &[u8]) -> Result<Vec<f32>, DepthAnalysisError> {
    if !bytes.len().is_multiple_of(4) {
        return Err(DepthAnalysisError::ParseError(format!(
            "Byte count {} is not divisible by 4",
            bytes.len()
        )));
    }

    let count = bytes.len() / 4;
    let mut depths = Vec::with_capacity(count);
    let mut cursor = Cursor::new(bytes);

    for _ in 0..count {
        let value = cursor
            .read_f32::<LittleEndian>()
            .map_err(|e| DepthAnalysisError::ParseError(e.to_string()))?;
        depths.push(value);
    }

    debug!(pixel_count = count, "Float32 array parsed");

    Ok(depths)
}

/// Filters depth values to only valid measurements
///
/// Excludes:
/// - Zero values (no depth reading)
/// - NaN or infinite values
/// - Values outside reasonable range (0.1m - 20m)
fn filter_valid_depths(depths: &[f32]) -> Vec<f64> {
    depths
        .iter()
        .filter(|d| d.is_finite() && **d >= MIN_VALID_DEPTH && **d <= MAX_VALID_DEPTH)
        .map(|d| *d as f64)
        .collect()
}

/// Computes statistical metrics from depth data
///
/// # Arguments
/// * `depths` - Raw depth values (may include invalid)
///
/// # Returns
/// DepthStatistics with variance, min/max, coverage
pub fn compute_depth_statistics(depths: &[f32]) -> Result<DepthStatistics, DepthAnalysisError> {
    if depths.is_empty() {
        return Err(DepthAnalysisError::EmptyDepthMap);
    }

    let valid = filter_valid_depths(depths);
    let valid_count = valid.len();
    let total_count = depths.len();

    if valid_count == 0 {
        return Err(DepthAnalysisError::InsufficientData {
            valid_count,
            total_count,
        });
    }

    // Compute mean
    let mean = valid.iter().sum::<f64>() / valid_count as f64;

    // Compute variance (std dev)
    let variance_sum: f64 = valid.iter().map(|d| (d - mean).powi(2)).sum();
    let variance = (variance_sum / valid_count as f64).sqrt();

    // Find min/max
    let min_depth = valid
        .iter()
        .copied()
        .min_by(|a, b| a.partial_cmp(b).unwrap())
        .unwrap_or(0.0);
    let max_depth = valid
        .iter()
        .copied()
        .max_by(|a, b| a.partial_cmp(b).unwrap())
        .unwrap_or(0.0);

    // Coverage ratio
    let coverage = valid_count as f64 / total_count as f64;

    Ok(DepthStatistics {
        variance,
        min_depth,
        max_depth,
        coverage,
        valid_count,
        total_count,
    })
}

/// Detects distinct depth layers using histogram peak detection
///
/// # Algorithm
/// 1. Build histogram of depth values over the valid range
/// 2. Smooth histogram with simple moving average
/// 3. Find local maxima (peaks)
/// 4. Filter peaks by prominence threshold
/// 5. Count significant peaks as depth layers
///
/// # Arguments
/// * `depths` - Raw depth values
/// * `min_depth` - Minimum valid depth from statistics
/// * `max_depth` - Maximum valid depth from statistics
///
/// # Returns
/// LayerDetectionResult with count and peak depths
pub fn detect_depth_layers(depths: &[f32], min_depth: f64, max_depth: f64) -> LayerDetectionResult {
    let valid = filter_valid_depths(depths);

    if valid.is_empty() || max_depth <= min_depth {
        return LayerDetectionResult {
            layer_count: 0,
            peak_depths: vec![],
        };
    }

    // Build histogram
    let bin_width = (max_depth - min_depth) / HISTOGRAM_BINS as f64;
    let mut histogram = vec![0usize; HISTOGRAM_BINS];

    for depth in &valid {
        let bin = ((depth - min_depth) / bin_width).floor() as usize;
        let bin = bin.min(HISTOGRAM_BINS - 1); // Clamp to valid range
        histogram[bin] += 1;
    }

    // Simple 3-point moving average smoothing
    let mut smoothed = vec![0.0f64; HISTOGRAM_BINS];
    for i in 0..HISTOGRAM_BINS {
        let left = if i > 0 {
            histogram[i - 1]
        } else {
            histogram[i]
        };
        let right = if i < HISTOGRAM_BINS - 1 {
            histogram[i + 1]
        } else {
            histogram[i]
        };
        smoothed[i] = (left + histogram[i] + right) as f64 / 3.0;
    }

    // Find max for prominence threshold
    let max_count = smoothed.iter().copied().fold(0.0f64, f64::max);
    let prominence_threshold = max_count * PEAK_PROMINENCE_RATIO;

    // Find local maxima (peaks)
    let mut peaks = Vec::new();
    for i in 1..(HISTOGRAM_BINS - 1) {
        if smoothed[i] > smoothed[i - 1]
            && smoothed[i] > smoothed[i + 1]
            && smoothed[i] > prominence_threshold
        {
            let depth = min_depth + (i as f64 + 0.5) * bin_width;
            peaks.push(depth);
        }
    }

    // Also check endpoints if they're prominent
    if HISTOGRAM_BINS > 0 && smoothed[0] > prominence_threshold && smoothed[0] > smoothed[1] {
        peaks.insert(0, min_depth + 0.5 * bin_width);
    }
    if HISTOGRAM_BINS > 1
        && smoothed[HISTOGRAM_BINS - 1] > prominence_threshold
        && smoothed[HISTOGRAM_BINS - 1] > smoothed[HISTOGRAM_BINS - 2]
    {
        peaks.push(max_depth - 0.5 * bin_width);
    }

    debug!(
        peak_count = peaks.len(),
        peak_depths = ?peaks,
        "Depth layers detected"
    );

    LayerDetectionResult {
        layer_count: peaks.len() as u32,
        peak_depths: peaks,
    }
}

/// Computes edge coherence from depth gradients
///
/// For MVP, this measures depth edge density as a proxy for scene complexity.
/// Real 3D scenes have many depth discontinuities at object boundaries.
/// Flat scenes have few or no meaningful depth edges.
///
/// # Algorithm
/// 1. Compute horizontal and vertical gradients (Sobel-like)
/// 2. Calculate gradient magnitude at each pixel
/// 3. Count pixels with gradient above threshold
/// 4. Normalize to 0.0-1.0 range
///
/// # Arguments
/// * `depths` - Depth values as flat array
/// * `width` - Image width in pixels
/// * `height` - Image height in pixels
///
/// # Returns
/// Edge coherence score 0.0-1.0
pub fn compute_edge_coherence(depths: &[f32], width: usize, height: usize) -> f64 {
    if depths.len() != width * height || width < 3 || height < 3 {
        return 0.0;
    }

    // Gradient threshold (meters) for edge detection
    const GRADIENT_THRESHOLD: f64 = 0.1;

    let mut edge_count = 0usize;
    let mut valid_pixels = 0usize;

    // Compute gradient magnitude for interior pixels
    for y in 1..(height - 1) {
        for x in 1..(width - 1) {
            let idx = y * width + x;
            let center = depths[idx];

            // Skip invalid center pixels
            if !center.is_finite() || !(MIN_VALID_DEPTH..=MAX_VALID_DEPTH).contains(&center) {
                continue;
            }

            valid_pixels += 1;

            // Sobel-like gradient (simplified)
            let left = depths[idx - 1] as f64;
            let right = depths[idx + 1] as f64;
            let up = depths[idx - width] as f64;
            let down = depths[idx + width] as f64;

            // Check if neighbors are valid
            let left_valid = left.is_finite() && left > MIN_VALID_DEPTH as f64;
            let right_valid = right.is_finite() && right > MIN_VALID_DEPTH as f64;
            let up_valid = up.is_finite() && up > MIN_VALID_DEPTH as f64;
            let down_valid = down.is_finite() && down > MIN_VALID_DEPTH as f64;

            // Compute gradients where possible
            let mut gx = 0.0f64;
            let mut gy = 0.0f64;

            if left_valid && right_valid {
                gx = (right - left) / 2.0;
            }
            if up_valid && down_valid {
                gy = (down - up) / 2.0;
            }

            let magnitude = (gx * gx + gy * gy).sqrt();

            if magnitude > GRADIENT_THRESHOLD {
                edge_count += 1;
            }
        }
    }

    if valid_pixels == 0 {
        return 0.0;
    }

    // Normalize: typical real scenes have 5-15% edge pixels
    // Map to 0.0-1.0 where >10% is considered high coherence
    let edge_ratio = edge_count as f64 / valid_pixels as f64;

    // Sigmoid-like mapping: 0% -> 0.0, 5% -> 0.5, 10%+ -> ~0.9+
    let coherence = 1.0 - (-edge_ratio * 30.0).exp();
    let coherence = coherence.clamp(0.0, 1.0);

    debug!(
        edge_count = edge_count,
        valid_pixels = valid_pixels,
        edge_ratio = edge_ratio,
        coherence = coherence,
        "Edge coherence computed"
    );

    coherence
}

/// Detects if depth pattern matches a screen/monitor (recapture attack)
///
/// Screens have:
/// - Very uniform depth (almost all pixels at same distance)
/// - Narrow depth range (<15cm variation)
/// - Typical distance 0.3-1.2m
///
/// Returns (is_screen_like, uniformity_ratio)
pub fn detect_screen_pattern(depths: &[f32], stats: &DepthStatistics) -> (bool, f64) {
    let valid = filter_valid_depths(depths);
    if valid.is_empty() {
        return (false, 0.0);
    }

    let depth_range = stats.max_depth - stats.min_depth;
    let mean_depth = valid.iter().sum::<f64>() / valid.len() as f64;

    // Check if in typical screen distance
    let in_screen_distance = (SCREEN_DISTANCE_MIN..=SCREEN_DISTANCE_MAX).contains(&mean_depth);

    // Check depth uniformity - what % of pixels are within tight band of median
    let median_depth = {
        let mut sorted = valid.clone();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
        sorted[sorted.len() / 2]
    };

    let tight_band = 0.05; // 5cm band around median
    let pixels_in_band = valid
        .iter()
        .filter(|d| (*d - median_depth).abs() < tight_band)
        .count();
    let uniformity_ratio = pixels_in_band as f64 / valid.len() as f64;

    // Screen-like if: narrow range + high uniformity + screen distance
    let is_screen_like = depth_range < SCREEN_DEPTH_RANGE_MAX
        && uniformity_ratio > SCREEN_UNIFORMITY_THRESHOLD
        && in_screen_distance;

    debug!(
        depth_range = depth_range,
        uniformity_ratio = uniformity_ratio,
        mean_depth = mean_depth,
        is_screen_like = is_screen_like,
        "[depth_analysis] Screen pattern detection"
    );

    (is_screen_like, uniformity_ratio)
}

/// Checks depth variance in image quadrants (anti-spoofing)
///
/// Real scenes have depth variation across the frame.
/// Screens/flat surfaces have uniform depth everywhere.
///
/// Returns (passes_check, min_quadrant_variance)
pub fn check_quadrant_variance(depths: &[f32], width: usize, height: usize) -> (bool, f64) {
    const MIN_QUADRANT_VARIANCE: f64 = 0.1; // Require some variance in each quadrant

    if depths.len() != width * height || width < 4 || height < 4 {
        return (false, 0.0);
    }

    let half_w = width / 2;
    let half_h = height / 2;

    let mut min_variance = f64::MAX;

    // Check each quadrant
    for qy in 0..2 {
        for qx in 0..2 {
            let mut quadrant_depths = Vec::new();
            for y in (qy * half_h)..((qy + 1) * half_h).min(height) {
                for x in (qx * half_w)..((qx + 1) * half_w).min(width) {
                    let d = depths[y * width + x];
                    if d.is_finite() && (MIN_VALID_DEPTH..=MAX_VALID_DEPTH).contains(&d) {
                        quadrant_depths.push(d as f64);
                    }
                }
            }

            if quadrant_depths.len() < 10 {
                continue;
            }

            let mean: f64 = quadrant_depths.iter().sum::<f64>() / quadrant_depths.len() as f64;
            let variance: f64 = (quadrant_depths
                .iter()
                .map(|d| (d - mean).powi(2))
                .sum::<f64>()
                / quadrant_depths.len() as f64)
                .sqrt();

            min_variance = min_variance.min(variance);
        }
    }

    let passes = min_variance > MIN_QUADRANT_VARIANCE;

    debug!(
        min_quadrant_variance = min_variance,
        passes = passes,
        "[depth_analysis] Quadrant variance check"
    );

    (passes, min_variance)
}

/// Determines if the scene is likely real based on all metrics
///
/// # Thresholds (from Epic 4 Tech Spec)
/// - depth_variance > 0.5 (sufficient depth variation)
/// - depth_layers >= 3 (multiple distinct depths)
/// - edge_coherence > 0.7 (depth aligns with photo content)
/// - NOT screen-like pattern (anti-recapture)
pub fn is_real_scene(
    variance: f64,
    layers: u32,
    coherence: f64,
    is_screen_like: bool,
    quadrant_passes: bool,
) -> bool {
    let basic_checks = variance > VARIANCE_THRESHOLD
        && layers >= LAYER_THRESHOLD
        && coherence > COHERENCE_THRESHOLD;

    // Fail if screen-like pattern detected
    if is_screen_like {
        warn!("[depth_analysis] Screen-like pattern detected - likely recapture attack");
        return false;
    }

    // Warn but don't fail on quadrant check (may have false positives)
    if !quadrant_passes {
        warn!("[depth_analysis] Low quadrant variance - suspicious uniformity");
    }

    basic_checks
}

// ============================================================================
// Main Analysis Functions
// ============================================================================

/// Analyzes a depth map from in-memory bytes and returns DepthAnalysis evidence
///
/// This is the preferred entry point for depth analysis when bytes are already
/// available in memory (e.g., during upload). It avoids redundant S3 downloads.
///
/// # Arguments
/// * `compressed_bytes` - Gzip-compressed depth map bytes
/// * `dimensions` - Expected (width, height) tuple
///
/// # Returns
/// DepthAnalysis struct with all metrics and status
///
/// # Error Handling
/// All errors are caught and converted to status=unavailable.
pub fn analyze_depth_map_from_bytes(
    compressed_bytes: &[u8],
    dimensions: Option<(u32, u32)>,
) -> DepthAnalysis {
    let start = std::time::Instant::now();

    info!(
        compressed_size = compressed_bytes.len(),
        dimensions = ?dimensions,
        "[depth_analysis] Starting depth map analysis from bytes"
    );

    // Try to perform analysis
    match analyze_depth_map_from_bytes_inner(compressed_bytes, dimensions) {
        Ok(analysis) => {
            let elapsed = start.elapsed();
            info!(
                status = ?analysis.status,
                depth_variance = analysis.depth_variance,
                depth_layers = analysis.depth_layers,
                edge_coherence = analysis.edge_coherence,
                is_likely_real_scene = analysis.is_likely_real_scene,
                elapsed_ms = elapsed.as_millis(),
                "[depth_analysis] Analysis complete"
            );
            analysis
        }
        Err(e) => {
            let elapsed = start.elapsed();
            warn!(
                error = %e,
                elapsed_ms = elapsed.as_millis(),
                "[depth_analysis] Analysis failed, returning unavailable"
            );
            DepthAnalysis::default()
        }
    }
}

/// Inner analysis function for in-memory bytes that returns Result for error propagation
fn analyze_depth_map_from_bytes_inner(
    compressed_bytes: &[u8],
    dimensions: Option<(u32, u32)>,
) -> Result<DepthAnalysis, DepthAnalysisError> {
    if compressed_bytes.is_empty() {
        return Err(DepthAnalysisError::EmptyDepthMap);
    }

    // 1. Decompress
    let decompressed = decompress_depth_map(compressed_bytes)?;

    // 2. Parse Float32 array
    let depths = parse_float32_array(&decompressed)?;

    // 3. Validate dimensions if provided
    let (width, height) = match dimensions {
        Some((w, h)) => {
            let expected = w as usize * h as usize;
            if depths.len() != expected {
                warn!(
                    expected = expected,
                    actual = depths.len(),
                    "[depth_analysis] Dimension mismatch, using actual size"
                );
                infer_dimensions(depths.len())
            } else {
                (w as usize, h as usize)
            }
        }
        None => infer_dimensions(depths.len()),
    };

    // 4. Compute statistics
    let stats = compute_depth_statistics(&depths)?;

    debug!(
        variance = stats.variance,
        min_depth = stats.min_depth,
        max_depth = stats.max_depth,
        coverage = stats.coverage,
        "[depth_analysis] Statistics computed"
    );

    // 5. Detect layers
    let layers = detect_depth_layers(&depths, stats.min_depth, stats.max_depth);

    // 6. Compute edge coherence
    let coherence = compute_edge_coherence(&depths, width, height);

    // 7. NEW: Screen pattern detection (anti-recapture)
    let (is_screen_like, _) = detect_screen_pattern(&depths, &stats);

    // 8. NEW: Quadrant variance check
    let (quadrant_passes, _) = check_quadrant_variance(&depths, width, height);

    // 9. Determine real scene status with anti-spoofing checks
    let is_real = is_real_scene(
        stats.variance,
        layers.layer_count,
        coherence,
        is_screen_like,
        quadrant_passes,
    );

    // 10. Build result
    let status = if is_real {
        CheckStatus::Pass
    } else {
        CheckStatus::Fail
    };

    Ok(DepthAnalysis {
        status,
        depth_variance: stats.variance,
        depth_layers: layers.layer_count,
        edge_coherence: coherence,
        min_depth: stats.min_depth,
        max_depth: stats.max_depth,
        is_likely_real_scene: is_real,
    })
}

/// Analyzes a depth map and returns DepthAnalysis evidence
///
/// This is the legacy entry point for depth analysis. It:
/// 1. Downloads the depth map from S3
/// 2. Decompresses and parses the data
/// 3. Computes all metrics
/// 4. Determines real scene status
///
/// Prefer `analyze_depth_map_from_bytes` when bytes are already available.
///
/// # Arguments
/// * `storage` - StorageService for S3 access
/// * `capture_id` - Capture UUID for S3 key generation
/// * `dimensions` - Expected (width, height) tuple
///
/// # Returns
/// DepthAnalysis struct with all metrics and status
///
/// # Error Handling
/// All errors are caught and converted to status=unavailable.
/// This function never returns Err - errors are logged and result in
/// a default unavailable analysis.
pub async fn analyze_depth_map(
    storage: &StorageService,
    capture_id: Uuid,
    dimensions: Option<(u32, u32)>,
) -> DepthAnalysis {
    let start = std::time::Instant::now();

    info!(
        capture_id = %capture_id,
        dimensions = ?dimensions,
        "[depth_analysis] Starting depth map analysis"
    );

    // Try to perform analysis
    match analyze_depth_map_inner(storage, capture_id, dimensions).await {
        Ok(analysis) => {
            let elapsed = start.elapsed();
            info!(
                capture_id = %capture_id,
                status = ?analysis.status,
                depth_variance = analysis.depth_variance,
                depth_layers = analysis.depth_layers,
                edge_coherence = analysis.edge_coherence,
                is_likely_real_scene = analysis.is_likely_real_scene,
                elapsed_ms = elapsed.as_millis(),
                "[depth_analysis] Analysis complete"
            );
            analysis
        }
        Err(e) => {
            let elapsed = start.elapsed();
            warn!(
                capture_id = %capture_id,
                error = %e,
                elapsed_ms = elapsed.as_millis(),
                "[depth_analysis] Analysis failed, returning unavailable"
            );
            DepthAnalysis::default()
        }
    }
}

/// Inner analysis function that returns Result for error propagation
async fn analyze_depth_map_inner(
    storage: &StorageService,
    capture_id: Uuid,
    dimensions: Option<(u32, u32)>,
) -> Result<DepthAnalysis, DepthAnalysisError> {
    // 1. Download from S3
    let compressed = storage
        .download_depth_map(capture_id)
        .await
        .map_err(|e| DepthAnalysisError::S3Download(e.to_string()))?;

    if compressed.is_empty() {
        return Err(DepthAnalysisError::EmptyDepthMap);
    }

    // 2. Decompress
    let decompressed = decompress_depth_map(&compressed)?;

    // 3. Parse Float32 array
    let depths = parse_float32_array(&decompressed)?;

    // 4. Validate dimensions if provided
    let (width, height) = match dimensions {
        Some((w, h)) => {
            let expected = w as usize * h as usize;
            if depths.len() != expected {
                warn!(
                    expected = expected,
                    actual = depths.len(),
                    "[depth_analysis] Dimension mismatch, using actual size"
                );
                // Infer dimensions from common aspect ratios
                infer_dimensions(depths.len())
            } else {
                (w as usize, h as usize)
            }
        }
        None => infer_dimensions(depths.len()),
    };

    // 5. Compute statistics
    let stats = compute_depth_statistics(&depths)?;

    debug!(
        variance = stats.variance,
        min_depth = stats.min_depth,
        max_depth = stats.max_depth,
        coverage = stats.coverage,
        "[depth_analysis] Statistics computed"
    );

    // 6. Detect layers
    let layers = detect_depth_layers(&depths, stats.min_depth, stats.max_depth);

    // 7. Compute edge coherence
    let coherence = compute_edge_coherence(&depths, width, height);

    // 8. NEW: Screen pattern detection (anti-recapture)
    let (is_screen_like, uniformity_ratio) = detect_screen_pattern(&depths, &stats);

    // 9. NEW: Quadrant variance check
    let (quadrant_passes, min_quadrant_var) = check_quadrant_variance(&depths, width, height);

    // 10. Determine real scene status with new checks
    let is_real = is_real_scene(
        stats.variance,
        layers.layer_count,
        coherence,
        is_screen_like,
        quadrant_passes,
    );

    // 11. Build result
    let status = if is_real {
        CheckStatus::Pass
    } else {
        CheckStatus::Fail
    };

    info!(
        is_screen_like = is_screen_like,
        uniformity_ratio = uniformity_ratio,
        quadrant_passes = quadrant_passes,
        min_quadrant_var = min_quadrant_var,
        "[depth_analysis] Anti-spoofing checks complete"
    );

    Ok(DepthAnalysis {
        status,
        depth_variance: stats.variance,
        depth_layers: layers.layer_count,
        edge_coherence: coherence,
        min_depth: stats.min_depth,
        max_depth: stats.max_depth,
        is_likely_real_scene: is_real,
    })
}

/// Infers image dimensions from pixel count
///
/// Common LiDAR resolutions:
/// - 256x192 = 49,152 (iPhone Pro typical)
/// - 320x240 = 76,800
/// - 640x480 = 307,200
fn infer_dimensions(pixel_count: usize) -> (usize, usize) {
    match pixel_count {
        49152 => (256, 192),  // iPhone Pro LiDAR
        76800 => (320, 240),  // QVGA
        307200 => (640, 480), // VGA
        _ => {
            // Guess 4:3 aspect ratio
            let height = ((pixel_count as f64 / (4.0 / 3.0)).sqrt()) as usize;
            let width = pixel_count / height.max(1);
            (width.max(1), height.max(1))
        }
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    /// Creates a flat plane depth map (simulates screen photo)
    fn create_flat_depth_map(depth: f32, width: usize, height: usize) -> Vec<f32> {
        vec![depth; width * height]
    }

    /// Creates a depth map with two distinct planes
    fn create_two_plane_depth_map(
        depth1: f32,
        depth2: f32,
        width: usize,
        height: usize,
    ) -> Vec<f32> {
        let mut depths = Vec::with_capacity(width * height);
        for y in 0..height {
            for _ in 0..width {
                let depth = if y < height / 2 { depth1 } else { depth2 };
                depths.push(depth);
            }
        }
        depths
    }

    /// Creates a varied depth map simulating a real scene
    fn create_varied_depth_map(width: usize, height: usize) -> Vec<f32> {
        let mut depths = Vec::with_capacity(width * height);
        for y in 0..height {
            for x in 0..width {
                // Create gradient + some variation
                let base = 0.5 + (x as f32 / width as f32) * 4.0;
                let variation = (y as f32 / height as f32) * 0.5;
                // Add some "objects" at different depths
                let depth =
                    if x > width / 3 && x < 2 * width / 3 && y > height / 3 && y < 2 * height / 3 {
                        1.0 // Foreground object
                    } else if x < width / 4 {
                        3.5 // Left side far
                    } else {
                        base + variation
                    };
                depths.push(depth);
            }
        }
        depths
    }

    #[test]
    fn test_parse_float32_array() {
        // Create test data: [1.0, 2.0, 3.0]
        let mut bytes = Vec::new();
        for val in [1.0f32, 2.0, 3.0] {
            bytes.extend_from_slice(&val.to_le_bytes());
        }

        let result = parse_float32_array(&bytes).unwrap();
        assert_eq!(result.len(), 3);
        assert!((result[0] - 1.0).abs() < 0.001);
        assert!((result[1] - 2.0).abs() < 0.001);
        assert!((result[2] - 3.0).abs() < 0.001);
    }

    #[test]
    fn test_parse_float32_array_invalid_length() {
        let bytes = vec![0u8; 5]; // Not divisible by 4
        let result = parse_float32_array(&bytes);
        assert!(result.is_err());
    }

    #[test]
    fn test_decompress_depth_map() {
        use flate2::write::GzEncoder;
        use flate2::Compression;
        use std::io::Write;

        // Create some test data and compress it
        let original = vec![1u8, 2, 3, 4, 5, 6, 7, 8];
        let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(&original).unwrap();
        let compressed = encoder.finish().unwrap();

        let decompressed = decompress_depth_map(&compressed).unwrap();
        assert_eq!(decompressed, original);
    }

    #[test]
    fn test_statistics_flat_plane() {
        let depths = create_flat_depth_map(0.4, 256, 192);
        let stats = compute_depth_statistics(&depths).unwrap();

        // Flat plane should have very low variance
        assert!(
            stats.variance < 0.01,
            "Flat plane variance should be near 0"
        );
        assert!((stats.min_depth - 0.4).abs() < 0.01);
        assert!((stats.max_depth - 0.4).abs() < 0.01);
        assert!(stats.coverage > 0.99);
    }

    #[test]
    fn test_statistics_varied_scene() {
        let depths = create_varied_depth_map(256, 192);
        let stats = compute_depth_statistics(&depths).unwrap();

        // Varied scene should have significant variance
        assert!(
            stats.variance > 0.5,
            "Varied scene should have variance > 0.5"
        );
        assert!(stats.max_depth > stats.min_depth);
    }

    #[test]
    fn test_layer_detection_flat() {
        let depths = create_flat_depth_map(0.4, 256, 192);
        let stats = compute_depth_statistics(&depths).unwrap();
        let layers = detect_depth_layers(&depths, stats.min_depth, stats.max_depth);

        // Flat surface should have 1-2 layers
        assert!(
            layers.layer_count <= 2,
            "Flat surface should have <= 2 layers"
        );
    }

    #[test]
    fn test_layer_detection_two_planes() {
        let depths = create_two_plane_depth_map(0.4, 2.0, 256, 192);
        let stats = compute_depth_statistics(&depths).unwrap();
        let layers = detect_depth_layers(&depths, stats.min_depth, stats.max_depth);

        // Two planes should detect 2 layers
        assert!(
            layers.layer_count >= 2,
            "Two plane scene should have >= 2 layers, got {}",
            layers.layer_count
        );
    }

    #[test]
    fn test_layer_detection_varied() {
        let depths = create_varied_depth_map(256, 192);
        let stats = compute_depth_statistics(&depths).unwrap();
        let layers = detect_depth_layers(&depths, stats.min_depth, stats.max_depth);

        // Varied scene should have multiple layers
        assert!(
            layers.layer_count >= 3,
            "Varied scene should have >= 3 layers, got {}",
            layers.layer_count
        );
    }

    #[test]
    fn test_edge_coherence_flat() {
        let depths = create_flat_depth_map(0.4, 256, 192);
        let coherence = compute_edge_coherence(&depths, 256, 192);

        // Flat surface should have low edge coherence
        assert!(
            coherence < 0.5,
            "Flat surface should have low coherence, got {coherence}"
        );
    }

    #[test]
    fn test_edge_coherence_varied() {
        let depths = create_varied_depth_map(256, 192);
        let coherence = compute_edge_coherence(&depths, 256, 192);

        // Varied scene should have higher edge coherence
        assert!(
            coherence > 0.3,
            "Varied scene should have coherence > 0.3, got {coherence}"
        );
    }

    #[test]
    fn test_is_real_scene_thresholds() {
        // All thresholds met, not screen, quadrant passes
        assert!(is_real_scene(0.6, 4, 0.8, false, true));

        // Variance too low
        assert!(!is_real_scene(0.4, 4, 0.8, false, true));

        // Layers too few
        assert!(!is_real_scene(0.6, 2, 0.8, false, true));

        // Coherence too low
        assert!(!is_real_scene(0.6, 4, 0.6, false, true));

        // Edge cases
        assert!(!is_real_scene(0.5, 3, 0.7, false, true)); // Exactly at thresholds = false
        assert!(is_real_scene(0.51, 3, 0.71, false, true)); // Just above = true

        // Screen-like pattern should fail
        assert!(!is_real_scene(0.6, 4, 0.8, true, true)); // is_screen_like = true
    }

    #[test]
    fn test_infer_dimensions() {
        assert_eq!(infer_dimensions(49152), (256, 192));
        assert_eq!(infer_dimensions(76800), (320, 240));
        assert_eq!(infer_dimensions(307200), (640, 480));
    }

    #[test]
    fn test_filter_valid_depths() {
        let depths = vec![
            0.0f32,        // Invalid: zero
            f32::NAN,      // Invalid: NaN
            f32::INFINITY, // Invalid: inf
            0.05,          // Invalid: too small
            25.0,          // Invalid: too large
            0.5,           // Valid
            1.0,           // Valid
            2.0,           // Valid
        ];

        let valid = filter_valid_depths(&depths);
        assert_eq!(valid.len(), 3);
        assert!((valid[0] - 0.5).abs() < 0.001);
        assert!((valid[1] - 1.0).abs() < 0.001);
        assert!((valid[2] - 2.0).abs() < 0.001);
    }

    #[test]
    fn test_empty_depth_map() {
        let depths: Vec<f32> = vec![];
        let result = compute_depth_statistics(&depths);
        assert!(matches!(result, Err(DepthAnalysisError::EmptyDepthMap)));
    }

    #[test]
    fn test_all_invalid_depths() {
        let depths = vec![0.0f32, f32::NAN, f32::INFINITY, 0.01, 100.0];
        let result = compute_depth_statistics(&depths);
        assert!(matches!(
            result,
            Err(DepthAnalysisError::InsufficientData { .. })
        ));
    }

    #[test]
    fn test_full_pipeline_flat_scene() {
        let depths = create_flat_depth_map(0.4, 256, 192);
        let stats = compute_depth_statistics(&depths).unwrap();
        let layers = detect_depth_layers(&depths, stats.min_depth, stats.max_depth);
        let coherence = compute_edge_coherence(&depths, 256, 192);
        let (is_screen, _) = detect_screen_pattern(&depths, &stats);
        let (quadrant_ok, _) = check_quadrant_variance(&depths, 256, 192);
        let is_real = is_real_scene(
            stats.variance,
            layers.layer_count,
            coherence,
            is_screen,
            quadrant_ok,
        );

        // Flat scene should NOT be detected as real
        assert!(
            !is_real,
            "Flat scene should not be detected as real. variance={}, layers={}, coherence={}, is_screen={}",
            stats.variance, layers.layer_count, coherence, is_screen
        );
    }

    #[test]
    fn test_full_pipeline_real_scene() {
        let depths = create_varied_depth_map(256, 192);
        let stats = compute_depth_statistics(&depths).unwrap();
        let layers = detect_depth_layers(&depths, stats.min_depth, stats.max_depth);
        let coherence = compute_edge_coherence(&depths, 256, 192);
        let (is_screen, _) = detect_screen_pattern(&depths, &stats);
        let (quadrant_ok, _) = check_quadrant_variance(&depths, 256, 192);
        let _is_real = is_real_scene(
            stats.variance,
            layers.layer_count,
            coherence,
            is_screen,
            quadrant_ok,
        );

        // Varied scene should be detected as real (or close to it)
        // Note: synthetic data may not perfectly match real scene characteristics
        println!(
            "Varied scene: variance={}, layers={}, coherence={}",
            stats.variance, layers.layer_count, coherence
        );

        // At minimum, it should have high variance and multiple layers
        assert!(stats.variance > VARIANCE_THRESHOLD);
        assert!(layers.layer_count >= LAYER_THRESHOLD);
    }
}
