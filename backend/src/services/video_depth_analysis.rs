//! Video Depth Analysis Service (Story 7-9)
//!
//! Analyzes temporal depth consistency across video keyframes to detect
//! manipulation attempts that single-frame analysis would miss:
//! - Splice attacks (footage from different scenes stitched together)
//! - Frame insertion (foreign frames inserted into genuine recording)
//! - Temporal discontinuities (impossible depth jumps between frames)
//! - Motion inconsistencies (depth motion that doesn't match scene)
//!
//! ## Analysis Pipeline
//! 1. Decompress gzipped depth blob
//! 2. Parse header and extract keyframes
//! 3. Sample frames at 1fps (every 10th keyframe)
//! 4. Compute depth_consistency (histogram comparison)
//! 5. Compute motion_coherence (depth motion patterns)
//! 6. Compute scene_stability (impossible jump detection)
//! 7. Flag suspicious frames
//! 8. Return VideoDepthAnalysis result

use byteorder::{LittleEndian, ReadBytesExt};
use flate2::read::GzDecoder;
use std::io::{Cursor, Read};
use tracing::{debug, info, warn};

use crate::types::video_depth_analysis::{
    DepthDataHeader, DepthFrameIndex, DepthKeyframe, FrameDepthAnalysis, VideoDepthAnalysis,
    VideoDepthAnalysisConfig, VideoDepthAnalysisError,
};

// ============================================================================
// Service Implementation
// ============================================================================

/// Service for analyzing temporal depth consistency in video captures
pub struct VideoDepthAnalysisService {
    config: VideoDepthAnalysisConfig,
}

impl VideoDepthAnalysisService {
    /// Create a new service with default configuration
    pub fn new() -> Self {
        Self {
            config: VideoDepthAnalysisConfig::default(),
        }
    }

    /// Create a new service with custom configuration
    pub fn with_config(config: VideoDepthAnalysisConfig) -> Self {
        Self { config }
    }

    /// Analyze depth keyframes from uploaded video capture
    ///
    /// This is the main entry point. It handles all errors gracefully,
    /// returning an "unavailable" result on failure rather than propagating errors.
    pub fn analyze(&self, depth_data: &[u8]) -> VideoDepthAnalysis {
        let start = std::time::Instant::now();

        info!(
            compressed_size = depth_data.len(),
            "[video_depth_analysis] Starting video depth analysis"
        );

        match self.analyze_inner(depth_data) {
            Ok(analysis) => {
                let elapsed = start.elapsed();
                info!(
                    depth_consistency = analysis.depth_consistency,
                    motion_coherence = analysis.motion_coherence,
                    scene_stability = analysis.scene_stability,
                    is_likely_real_scene = analysis.is_likely_real_scene,
                    suspicious_count = analysis.suspicious_frames.len(),
                    elapsed_ms = elapsed.as_millis(),
                    "[video_depth_analysis] Analysis complete"
                );
                analysis
            }
            Err(e) => {
                let elapsed = start.elapsed();
                warn!(
                    error = %e,
                    elapsed_ms = elapsed.as_millis(),
                    "[video_depth_analysis] Analysis failed, returning unavailable"
                );
                VideoDepthAnalysis::unavailable()
            }
        }
    }

    /// Inner analysis function that returns Result for error handling
    fn analyze_inner(
        &self,
        depth_data: &[u8],
    ) -> Result<VideoDepthAnalysis, VideoDepthAnalysisError> {
        if depth_data.is_empty() {
            return Err(VideoDepthAnalysisError::EmptyData);
        }

        // 1. Decompress
        let decompressed = decompress_depth_data(depth_data)?;

        // 2. Parse header and frames
        let keyframes = parse_depth_keyframes(&decompressed)?;

        if keyframes.is_empty() {
            return Err(VideoDepthAnalysisError::InsufficientFrames {
                count: 0,
                minimum: 2,
            });
        }

        // 3. Sample frames at configured rate
        let sampled_frames: Vec<&DepthKeyframe> = keyframes
            .iter()
            .enumerate()
            .filter(|(i, _)| *i % self.config.sample_rate as usize == 0)
            .map(|(_, f)| f)
            .collect();

        if sampled_frames.len() < 2 {
            // Need at least 2 frames for temporal analysis
            return Err(VideoDepthAnalysisError::InsufficientFrames {
                count: sampled_frames.len(),
                minimum: 2,
            });
        }

        debug!(
            total_frames = keyframes.len(),
            sampled_frames = sampled_frames.len(),
            "[video_depth_analysis] Frames sampled"
        );

        // 4. Compute per-frame analyses
        let frame_analyses = self.analyze_frames(&sampled_frames);

        // 5. Compute aggregate metrics
        let depth_consistency = self.compute_depth_consistency(&frame_analyses);
        let motion_coherence = self.compute_motion_coherence(&frame_analyses);
        let scene_stability = self.compute_scene_stability(&sampled_frames);

        // 6. Detect suspicious frames
        let suspicious_frames = self.detect_suspicious_frames(&frame_analyses, &sampled_frames);

        // 7. Determine if likely real scene
        let is_likely_real_scene = depth_consistency >= self.config.consistency_threshold
            && motion_coherence >= self.config.coherence_threshold
            && scene_stability >= self.config.stability_threshold
            && suspicious_frames.is_empty();

        Ok(VideoDepthAnalysis {
            frame_analyses,
            depth_consistency,
            motion_coherence,
            scene_stability,
            is_likely_real_scene,
            suspicious_frames,
        })
    }

    /// Analyze individual frames and compute per-frame metrics
    fn analyze_frames(&self, frames: &[&DepthKeyframe]) -> Vec<FrameDepthAnalysis> {
        let mut analyses = Vec::with_capacity(frames.len());
        let mut prev_histogram: Option<Vec<u32>> = None;

        for (i, frame) in frames.iter().enumerate() {
            let histogram = compute_depth_histogram(
                &frame.depth_data,
                self.config.histogram_bins,
                self.config.min_valid_depth,
                self.config.max_valid_depth,
            );

            // Compute local consistency with previous frame
            let local_consistency = if let Some(ref prev) = prev_histogram {
                compute_histogram_similarity(&histogram, prev)
            } else {
                1.0 // First frame has perfect consistency with itself
            };

            // Compute motion vector (simple block correlation)
            let motion_vector = if i > 0 {
                compute_motion_vector(frames[i - 1], frame)
            } else {
                None
            };

            analyses.push(FrameDepthAnalysis {
                frame_index: frame.index,
                timestamp: frame.timestamp,
                depth_histogram: histogram.clone(),
                motion_vector,
                local_consistency,
            });

            prev_histogram = Some(histogram);
        }

        analyses
    }

    /// Compute overall depth consistency score (0-1)
    fn compute_depth_consistency(&self, analyses: &[FrameDepthAnalysis]) -> f32 {
        if analyses.len() < 2 {
            return 1.0; // Single frame is perfectly consistent
        }

        let sum: f32 = analyses.iter().map(|a| a.local_consistency).sum();
        sum / analyses.len() as f32
    }

    /// Compute motion coherence score (0-1)
    fn compute_motion_coherence(&self, analyses: &[FrameDepthAnalysis]) -> f32 {
        let motion_vectors: Vec<(f32, f32)> =
            analyses.iter().filter_map(|a| a.motion_vector).collect();

        if motion_vectors.is_empty() {
            // No motion detected = static scene = coherent
            return 1.0;
        }

        if motion_vectors.len() < 2 {
            return 1.0;
        }

        // Check if motion vectors are consistent (similar direction/magnitude)
        let mut coherence_scores = Vec::new();

        for i in 1..motion_vectors.len() {
            let prev = motion_vectors[i - 1];
            let curr = motion_vectors[i];

            // Compute similarity between consecutive motion vectors
            let prev_mag = (prev.0 * prev.0 + prev.1 * prev.1).sqrt();
            let curr_mag = (curr.0 * curr.0 + curr.1 * curr.1).sqrt();

            if prev_mag < 0.01 && curr_mag < 0.01 {
                // Both nearly zero = consistent static
                coherence_scores.push(1.0);
            } else if prev_mag < 0.01 || curr_mag < 0.01 {
                // One is static, one is moving = transition
                coherence_scores.push(0.5);
            } else {
                // Both have motion - check direction similarity
                let dot = prev.0 * curr.0 + prev.1 * curr.1;
                let cos_sim = dot / (prev_mag * curr_mag);
                // Map cosine similarity [-1, 1] to [0, 1]
                coherence_scores.push((cos_sim + 1.0) / 2.0);
            }
        }

        coherence_scores.iter().sum::<f32>() / coherence_scores.len() as f32
    }

    /// Compute scene stability score (0-1)
    fn compute_scene_stability(&self, frames: &[&DepthKeyframe]) -> f32 {
        if frames.len() < 2 {
            return 1.0;
        }

        let mut frames_with_jumps = 0;

        for i in 1..frames.len() {
            let prev = &frames[i - 1];
            let curr = &frames[i];

            // Count pixels with impossible depth jumps
            let jump_count = count_depth_jumps(
                &prev.depth_data,
                &curr.depth_data,
                self.config.max_depth_jump,
                self.config.min_valid_depth,
                self.config.max_valid_depth,
            );

            let total_pixels = prev.depth_data.len().min(curr.depth_data.len());
            let jump_ratio = jump_count as f32 / total_pixels as f32;

            // Flag if >5% of pixels have impossible jumps
            if jump_ratio > 0.05 {
                frames_with_jumps += 1;
            }
        }

        // Score: proportion of frame pairs without jumps
        let total_pairs = frames.len() - 1;
        1.0 - (frames_with_jumps as f32 / total_pairs as f32)
    }

    /// Detect frames with anomalies
    fn detect_suspicious_frames(
        &self,
        analyses: &[FrameDepthAnalysis],
        frames: &[&DepthKeyframe],
    ) -> Vec<u32> {
        let mut suspicious = Vec::new();

        // Flag frames with low local consistency
        for analysis in analyses {
            if analysis.local_consistency < 0.5 {
                suspicious.push(analysis.frame_index);
            }
        }

        // Flag frames with large depth jumps
        for i in 1..frames.len() {
            let prev = &frames[i - 1];
            let curr = &frames[i];

            let jump_count = count_depth_jumps(
                &prev.depth_data,
                &curr.depth_data,
                self.config.max_depth_jump,
                self.config.min_valid_depth,
                self.config.max_valid_depth,
            );

            let total_pixels = prev.depth_data.len().min(curr.depth_data.len());
            let jump_ratio = jump_count as f32 / total_pixels as f32;

            if jump_ratio > 0.05 && !suspicious.contains(&curr.index) {
                suspicious.push(curr.index);
            }
        }

        suspicious.sort();
        suspicious.dedup();
        suspicious
    }
}

impl Default for VideoDepthAnalysisService {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Decompress gzipped depth data
fn decompress_depth_data(compressed: &[u8]) -> Result<Vec<u8>, VideoDepthAnalysisError> {
    let mut decoder = GzDecoder::new(compressed);
    let mut decompressed = Vec::new();

    decoder
        .read_to_end(&mut decompressed)
        .map_err(|e| VideoDepthAnalysisError::DecompressionError(e.to_string()))?;

    debug!(
        compressed_size = compressed.len(),
        decompressed_size = decompressed.len(),
        "[video_depth_analysis] Depth data decompressed"
    );

    Ok(decompressed)
}

/// Parse depth keyframes from decompressed blob
fn parse_depth_keyframes(data: &[u8]) -> Result<Vec<DepthKeyframe>, VideoDepthAnalysisError> {
    if data.len() < DepthDataHeader::SIZE {
        return Err(VideoDepthAnalysisError::InvalidFormat(
            "Data too small for header".to_string(),
        ));
    }

    let mut cursor = Cursor::new(data);

    // Parse header
    let mut magic = [0u8; 4];
    cursor
        .read_exact(&mut magic)
        .map_err(|e| VideoDepthAnalysisError::InvalidFormat(e.to_string()))?;

    if &magic != DepthDataHeader::MAGIC {
        return Err(VideoDepthAnalysisError::InvalidMagic(magic));
    }

    let version = cursor
        .read_u32::<LittleEndian>()
        .map_err(|e| VideoDepthAnalysisError::InvalidFormat(e.to_string()))?;

    if version != 1 {
        return Err(VideoDepthAnalysisError::UnsupportedVersion(version));
    }

    let frame_count = cursor
        .read_u32::<LittleEndian>()
        .map_err(|e| VideoDepthAnalysisError::InvalidFormat(e.to_string()))?;

    let width = cursor
        .read_u16::<LittleEndian>()
        .map_err(|e| VideoDepthAnalysisError::InvalidFormat(e.to_string()))?;

    let height = cursor
        .read_u16::<LittleEndian>()
        .map_err(|e| VideoDepthAnalysisError::InvalidFormat(e.to_string()))?;

    debug!(
        version = version,
        frame_count = frame_count,
        width = width,
        height = height,
        "[video_depth_analysis] Header parsed"
    );

    // Parse frame index
    let mut frame_indices = Vec::with_capacity(frame_count as usize);
    for _ in 0..frame_count {
        let timestamp = cursor
            .read_f64::<LittleEndian>()
            .map_err(|e| VideoDepthAnalysisError::InvalidFormat(e.to_string()))?;
        let offset = cursor
            .read_u32::<LittleEndian>()
            .map_err(|e| VideoDepthAnalysisError::InvalidFormat(e.to_string()))?;
        frame_indices.push(DepthFrameIndex { timestamp, offset });
    }

    // Parse frame data
    let frame_size = (width as usize) * (height as usize) * 4; // Float32 = 4 bytes
    let data_start = DepthDataHeader::SIZE + frame_count as usize * DepthFrameIndex::SIZE;

    let mut keyframes = Vec::with_capacity(frame_count as usize);
    for (i, index) in frame_indices.iter().enumerate() {
        let offset = data_start + index.offset as usize;

        if offset + frame_size > data.len() {
            return Err(VideoDepthAnalysisError::TruncatedFrame {
                index: i as u32,
                expected: frame_size,
                actual: data.len().saturating_sub(offset),
            });
        }

        let frame_bytes = &data[offset..offset + frame_size];
        let depth_data = parse_float32_array(frame_bytes)?;

        keyframes.push(DepthKeyframe {
            index: i as u32,
            timestamp: index.timestamp,
            depth_data,
            width: width as u32,
            height: height as u32,
        });
    }

    Ok(keyframes)
}

/// Parse raw bytes as Float32 array (little-endian)
fn parse_float32_array(bytes: &[u8]) -> Result<Vec<f32>, VideoDepthAnalysisError> {
    if !bytes.len().is_multiple_of(4) {
        return Err(VideoDepthAnalysisError::InvalidFormat(format!(
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
            .map_err(|e| VideoDepthAnalysisError::InvalidFormat(e.to_string()))?;
        depths.push(value);
    }

    Ok(depths)
}

/// Compute depth histogram for a frame
fn compute_depth_histogram(
    depths: &[f32],
    bins: usize,
    min_valid: f32,
    max_valid: f32,
) -> Vec<u32> {
    let mut histogram = vec![0u32; bins];
    let bin_width = (max_valid - min_valid) / bins as f32;

    for &depth in depths {
        if depth.is_finite() && depth >= min_valid && depth <= max_valid {
            let bin = ((depth - min_valid) / bin_width).floor() as usize;
            let bin = bin.min(bins - 1);
            histogram[bin] += 1;
        }
    }

    histogram
}

/// Compute similarity between two histograms using normalized intersection
fn compute_histogram_similarity(hist1: &[u32], hist2: &[u32]) -> f32 {
    if hist1.len() != hist2.len() || hist1.is_empty() {
        return 0.0;
    }

    // Histogram intersection
    let intersection: u32 = hist1
        .iter()
        .zip(hist2.iter())
        .map(|(a, b)| (*a).min(*b))
        .sum();
    let sum1: u32 = hist1.iter().sum();
    let sum2: u32 = hist2.iter().sum();

    if sum1 == 0 || sum2 == 0 {
        return 0.0;
    }

    // Normalize by minimum sum (Jaccard-like)
    let min_sum = sum1.min(sum2);
    intersection as f32 / min_sum as f32
}

/// Compute simple motion vector between two frames using block correlation
fn compute_motion_vector(prev: &DepthKeyframe, curr: &DepthKeyframe) -> Option<(f32, f32)> {
    // Downsample to 8x8 blocks for efficiency
    let block_size = 8;
    let prev_blocks = downsample_to_blocks(&prev.depth_data, prev.width, prev.height, block_size);
    let curr_blocks = downsample_to_blocks(&curr.depth_data, curr.width, curr.height, block_size);

    if prev_blocks.is_empty() || curr_blocks.is_empty() {
        return None;
    }

    // Simple centroid-based motion estimation
    let prev_centroid = compute_depth_centroid(&prev_blocks);
    let curr_centroid = compute_depth_centroid(&curr_blocks);

    let dx = curr_centroid.0 - prev_centroid.0;
    let dy = curr_centroid.1 - prev_centroid.1;

    // Normalize to [-1, 1] range based on block grid size
    let grid_width = prev.width as f32 / block_size as f32;
    let grid_height = prev.height as f32 / block_size as f32;

    Some((dx / grid_width, dy / grid_height))
}

/// Downsample depth frame to block averages
fn downsample_to_blocks(depths: &[f32], width: u32, height: u32, block_size: usize) -> Vec<f32> {
    let blocks_x = (width as usize) / block_size;
    let blocks_y = (height as usize) / block_size;
    let mut blocks = Vec::with_capacity(blocks_x * blocks_y);

    for by in 0..blocks_y {
        for bx in 0..blocks_x {
            let mut sum = 0.0f32;
            let mut count = 0;

            for dy in 0..block_size {
                for dx in 0..block_size {
                    let x = bx * block_size + dx;
                    let y = by * block_size + dy;
                    let idx = y * (width as usize) + x;

                    if idx < depths.len() {
                        let d = depths[idx];
                        if d.is_finite() && d > 0.1 && d < 20.0 {
                            sum += d;
                            count += 1;
                        }
                    }
                }
            }

            let avg = if count > 0 { sum / count as f32 } else { 0.0 };
            blocks.push(avg);
        }
    }

    blocks
}

/// Compute weighted centroid of depth values
fn compute_depth_centroid(blocks: &[f32]) -> (f32, f32) {
    let side = (blocks.len() as f32).sqrt() as usize;
    if side == 0 {
        return (0.0, 0.0);
    }

    let mut weighted_x = 0.0f32;
    let mut weighted_y = 0.0f32;
    let mut total_weight = 0.0f32;

    for (i, &depth) in blocks.iter().enumerate() {
        if depth > 0.0 {
            let x = (i % side) as f32;
            let y = (i / side) as f32;
            // Use inverse depth as weight (closer = more weight)
            let weight = 1.0 / depth;
            weighted_x += x * weight;
            weighted_y += y * weight;
            total_weight += weight;
        }
    }

    if total_weight > 0.0 {
        (weighted_x / total_weight, weighted_y / total_weight)
    } else {
        (side as f32 / 2.0, side as f32 / 2.0)
    }
}

/// Count pixels with depth jumps exceeding threshold
fn count_depth_jumps(
    prev: &[f32],
    curr: &[f32],
    max_jump: f32,
    min_valid: f32,
    max_valid: f32,
) -> usize {
    let mut count = 0;

    for (p, c) in prev.iter().zip(curr.iter()) {
        let p_valid = p.is_finite() && *p >= min_valid && *p <= max_valid;
        let c_valid = c.is_finite() && *c >= min_valid && *c <= max_valid;

        if p_valid && c_valid {
            let diff = (p - c).abs();
            if diff > max_jump {
                count += 1;
            }
        }
    }

    count
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use flate2::write::GzEncoder;
    use flate2::Compression;
    use std::io::Write;

    /// Create a mock depth data blob for testing
    fn create_mock_depth_blob(
        frame_count: u32,
        width: u16,
        height: u16,
        depth_value: f32,
    ) -> Vec<u8> {
        let frame_size = (width as usize) * (height as usize) * 4;
        let index_size = frame_count as usize * DepthFrameIndex::SIZE;
        let data_size = frame_count as usize * frame_size;
        let total_size = DepthDataHeader::SIZE + index_size + data_size;

        let mut data = Vec::with_capacity(total_size);

        // Write header
        data.extend_from_slice(DepthDataHeader::MAGIC);
        data.extend_from_slice(&1u32.to_le_bytes()); // version
        data.extend_from_slice(&frame_count.to_le_bytes());
        data.extend_from_slice(&width.to_le_bytes());
        data.extend_from_slice(&height.to_le_bytes());

        // Write frame index
        for i in 0..frame_count {
            let timestamp = i as f64 * 0.1; // 10fps
            let offset = i * frame_size as u32;
            data.extend_from_slice(&timestamp.to_le_bytes());
            data.extend_from_slice(&offset.to_le_bytes());
        }

        // Write frame data
        for _ in 0..frame_count {
            for _ in 0..(width as usize * height as usize) {
                data.extend_from_slice(&depth_value.to_le_bytes());
            }
        }

        // Compress
        let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(&data).unwrap();
        encoder.finish().unwrap()
    }

    /// Create a mock depth blob with varying depth values
    fn create_varied_depth_blob(frame_count: u32, width: u16, height: u16) -> Vec<u8> {
        let frame_size = (width as usize) * (height as usize) * 4;
        let index_size = frame_count as usize * DepthFrameIndex::SIZE;
        let data_size = frame_count as usize * frame_size;
        let total_size = DepthDataHeader::SIZE + index_size + data_size;

        let mut data = Vec::with_capacity(total_size);

        // Write header
        data.extend_from_slice(DepthDataHeader::MAGIC);
        data.extend_from_slice(&1u32.to_le_bytes());
        data.extend_from_slice(&frame_count.to_le_bytes());
        data.extend_from_slice(&width.to_le_bytes());
        data.extend_from_slice(&height.to_le_bytes());

        // Write frame index
        for i in 0..frame_count {
            let timestamp = i as f64 * 0.1;
            let offset = i * frame_size as u32;
            data.extend_from_slice(&timestamp.to_le_bytes());
            data.extend_from_slice(&offset.to_le_bytes());
        }

        // Write frame data with gradual variation
        for frame_idx in 0..frame_count {
            for y in 0..height {
                for x in 0..width {
                    // Create gradient + small per-frame variation
                    let base = 1.0 + (x as f32 / width as f32) * 3.0;
                    let variation = (frame_idx as f32 * 0.01) + (y as f32 / height as f32) * 0.5;
                    let depth = base + variation;
                    data.extend_from_slice(&depth.to_le_bytes());
                }
            }
        }

        // Compress
        let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(&data).unwrap();
        encoder.finish().unwrap()
    }

    #[test]
    fn test_service_creation() {
        let service = VideoDepthAnalysisService::new();
        assert_eq!(service.config.sample_rate, 10);

        let custom_config = VideoDepthAnalysisConfig {
            sample_rate: 5,
            ..Default::default()
        };
        let service = VideoDepthAnalysisService::with_config(custom_config);
        assert_eq!(service.config.sample_rate, 5);
    }

    #[test]
    fn test_analyze_empty_data() {
        let service = VideoDepthAnalysisService::new();
        let result = service.analyze(&[]);
        assert!(!result.is_valid());
    }

    #[test]
    fn test_analyze_invalid_gzip() {
        let service = VideoDepthAnalysisService::new();
        let result = service.analyze(&[1, 2, 3, 4]); // Not valid gzip
        assert!(!result.is_valid());
    }

    #[test]
    fn test_analyze_uniform_depth() {
        let service = VideoDepthAnalysisService::with_config(VideoDepthAnalysisConfig {
            sample_rate: 1, // Analyze every frame
            ..Default::default()
        });

        let blob = create_mock_depth_blob(15, 32, 24, 2.0); // 15 frames at uniform 2m depth
        let result = service.analyze(&blob);

        assert!(result.is_valid());
        assert!(
            result.depth_consistency > 0.9,
            "Uniform depth should have high consistency"
        );
        assert!(
            result.scene_stability > 0.9,
            "Uniform depth should have high stability"
        );
    }

    #[test]
    fn test_analyze_varied_depth() {
        let service = VideoDepthAnalysisService::with_config(VideoDepthAnalysisConfig {
            sample_rate: 1,
            ..Default::default()
        });

        let blob = create_varied_depth_blob(15, 32, 24);
        let result = service.analyze(&blob);

        assert!(result.is_valid());
        assert!(result.frame_analyses.len() >= 2);
        // Varied but smooth depth should still have good consistency
        assert!(result.depth_consistency > 0.5);
    }

    #[test]
    fn test_histogram_computation() {
        let depths = vec![1.0f32, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0];
        let histogram = compute_depth_histogram(&depths, 10, 0.1, 10.0);

        // Each depth value should fall into a different bin
        assert_eq!(histogram.len(), 10);
        let total: u32 = histogram.iter().sum();
        assert_eq!(total, 10);
    }

    #[test]
    fn test_histogram_similarity_identical() {
        let hist1 = vec![100u32, 200, 300, 400, 500];
        let hist2 = vec![100u32, 200, 300, 400, 500];

        let similarity = compute_histogram_similarity(&hist1, &hist2);
        assert!(
            (similarity - 1.0).abs() < 0.001,
            "Identical histograms should have similarity 1.0"
        );
    }

    #[test]
    fn test_histogram_similarity_different() {
        let hist1 = vec![100u32, 0, 0, 0, 0];
        let hist2 = vec![0u32, 0, 0, 0, 100];

        let similarity = compute_histogram_similarity(&hist1, &hist2);
        assert!(
            similarity < 0.1,
            "Very different histograms should have low similarity"
        );
    }

    #[test]
    fn test_depth_jump_counting() {
        let prev = vec![1.0f32, 2.0, 3.0, 4.0, 5.0];
        let curr = vec![1.1f32, 2.1, 6.0, 4.1, 5.1]; // Index 2 has 3m jump

        let count = count_depth_jumps(&prev, &curr, 2.0, 0.1, 10.0);
        assert_eq!(count, 1, "Should detect 1 jump exceeding 2m");
    }

    #[test]
    fn test_parse_depth_keyframes_invalid_magic() {
        let mut data = vec![0u8; 100];
        data[0..4].copy_from_slice(b"XXXX"); // Wrong magic

        let result = parse_depth_keyframes(&data);
        assert!(matches!(
            result,
            Err(VideoDepthAnalysisError::InvalidMagic(_))
        ));
    }

    #[test]
    fn test_downsample_to_blocks() {
        // 16x16 depth map
        let depths: Vec<f32> = (0..256).map(|i| 1.0 + (i as f32 / 256.0)).collect();
        let blocks = downsample_to_blocks(&depths, 16, 16, 8);

        // Should produce 2x2 = 4 blocks
        assert_eq!(blocks.len(), 4);
        // All blocks should have valid depth values
        assert!(blocks.iter().all(|&b| b > 0.0));
    }

    #[test]
    fn test_compute_depth_centroid() {
        // 3x3 grid with higher depth in top-left
        let blocks = vec![5.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0];
        let centroid = compute_depth_centroid(&blocks);

        // Centroid should be pulled toward top-left due to inverse depth weighting
        // But since top-left has HIGHER depth, it has LOWER weight
        // So centroid should actually be pulled AWAY from top-left
        assert!(centroid.0 > 0.5, "Centroid x should be > 0.5");
        assert!(centroid.1 > 0.5, "Centroid y should be > 0.5");
    }
}
