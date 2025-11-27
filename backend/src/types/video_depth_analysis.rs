//! Video Depth Analysis Types (Story 7-9)
//!
//! Types for temporal depth analysis across video keyframes.
//! Detects manipulation attempts that single-frame analysis would miss:
//! - Splice attacks (footage from different scenes)
//! - Frame insertion (foreign frames in genuine recording)
//! - Temporal discontinuities (impossible depth jumps)

use serde::{Deserialize, Serialize};
use thiserror::Error;

// ============================================================================
// Configuration
// ============================================================================

/// Configuration for video depth analysis
#[derive(Debug, Clone)]
pub struct VideoDepthAnalysisConfig {
    /// Sample rate: analyze every Nth keyframe (default: 10 = 1fps from 10fps keyframes)
    pub sample_rate: u32,
    /// Threshold for depth consistency (default: 0.7)
    pub consistency_threshold: f32,
    /// Threshold for motion coherence (default: 0.6)
    pub coherence_threshold: f32,
    /// Threshold for scene stability (default: 0.8)
    pub stability_threshold: f32,
    /// Maximum depth jump before flagging (meters)
    pub max_depth_jump: f32,
    /// Minimum valid depth value (meters)
    pub min_valid_depth: f32,
    /// Maximum valid depth value (meters)
    pub max_valid_depth: f32,
    /// Number of histogram bins
    pub histogram_bins: usize,
}

impl Default for VideoDepthAnalysisConfig {
    fn default() -> Self {
        Self {
            sample_rate: 10, // 1fps from 10fps keyframes
            consistency_threshold: 0.7,
            coherence_threshold: 0.6,
            stability_threshold: 0.8,
            max_depth_jump: 2.0, // 2 meters
            min_valid_depth: 0.1,
            max_valid_depth: 20.0,
            histogram_bins: 10, // 0-10m in 1m bins
        }
    }
}

// ============================================================================
// Data Structures
// ============================================================================

/// Header of the video depth data blob
#[derive(Debug, Clone)]
pub struct DepthDataHeader {
    /// Magic bytes "RLDP"
    pub magic: [u8; 4],
    /// Format version
    pub version: u32,
    /// Number of keyframes
    pub frame_count: u32,
    /// Width of each frame
    pub width: u16,
    /// Height of each frame
    pub height: u16,
}

impl DepthDataHeader {
    /// Expected magic bytes
    pub const MAGIC: &'static [u8; 4] = b"RLDP";
    /// Header size in bytes
    pub const SIZE: usize = 16;
}

/// Index entry for a single depth keyframe
#[derive(Debug, Clone)]
pub struct DepthFrameIndex {
    /// Timestamp in video (seconds)
    pub timestamp: f64,
    /// Byte offset in data section
    pub offset: u32,
}

impl DepthFrameIndex {
    /// Size of each index entry in bytes
    pub const SIZE: usize = 12;
}

/// A single depth keyframe extracted from video
#[derive(Debug, Clone)]
pub struct DepthKeyframe {
    /// Keyframe index (0-based)
    pub index: u32,
    /// Timestamp in video (seconds)
    pub timestamp: f64,
    /// Depth data as Float32 array
    pub depth_data: Vec<f32>,
    /// Frame width
    pub width: u32,
    /// Frame height
    pub height: u32,
}

/// Per-frame analysis results (for sampled frames)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FrameDepthAnalysis {
    /// Keyframe index
    pub frame_index: u32,
    /// Timestamp in video
    pub timestamp: f64,
    /// Depth histogram (10 bins from 0-10m)
    pub depth_histogram: Vec<u32>,
    /// Primary motion vector (dx, dy) from optical flow
    #[serde(skip_serializing_if = "Option::is_none")]
    pub motion_vector: Option<(f32, f32)>,
    /// Local depth consistency with previous frame (0-1)
    pub local_consistency: f32,
}

/// Complete video depth analysis results
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoDepthAnalysis {
    /// Per-frame analysis (sampled at 1fps)
    pub frame_analyses: Vec<FrameDepthAnalysis>,

    /// Depth consistency score (0-1)
    /// How stable is depth across frames?
    pub depth_consistency: f32,

    /// Motion coherence score (0-1)
    /// Does depth motion match expected patterns?
    pub motion_coherence: f32,

    /// Scene stability score (0-1)
    /// Are there impossible depth jumps?
    pub scene_stability: f32,

    /// Aggregate assessment
    pub is_likely_real_scene: bool,

    /// Frame indices with anomalies
    pub suspicious_frames: Vec<u32>,
}

impl Default for VideoDepthAnalysis {
    fn default() -> Self {
        Self {
            frame_analyses: vec![],
            depth_consistency: 0.0,
            motion_coherence: 0.0,
            scene_stability: 0.0,
            is_likely_real_scene: false,
            suspicious_frames: vec![],
        }
    }
}

impl VideoDepthAnalysis {
    /// Create a result indicating analysis was unavailable
    pub fn unavailable() -> Self {
        Self::default()
    }

    /// Check if this is a valid analysis result (not unavailable)
    pub fn is_valid(&self) -> bool {
        !self.frame_analyses.is_empty()
    }
}

// ============================================================================
// Error Types
// ============================================================================

/// Errors that can occur during video depth analysis
#[derive(Debug, Error)]
pub enum VideoDepthAnalysisError {
    #[error("Failed to decompress depth data: {0}")]
    DecompressionError(String),

    #[error("Invalid depth data format: {0}")]
    InvalidFormat(String),

    #[error("Invalid magic bytes: expected RLDP, got {0:?}")]
    InvalidMagic([u8; 4]),

    #[error("Unsupported format version: {0}")]
    UnsupportedVersion(u32),

    #[error("Insufficient frames for analysis: {count} frames (minimum: {minimum})")]
    InsufficientFrames { count: usize, minimum: usize },

    #[error("Frame data truncated at index {index}: expected {expected} bytes, got {actual}")]
    TruncatedFrame {
        index: u32,
        expected: usize,
        actual: usize,
    },

    #[error("Empty depth data")]
    EmptyData,

    #[error("Analysis computation failed: {0}")]
    ComputationError(String),
}

// ============================================================================
// Unit Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = VideoDepthAnalysisConfig::default();
        assert_eq!(config.sample_rate, 10);
        assert!((config.consistency_threshold - 0.7).abs() < 0.001);
        assert!((config.coherence_threshold - 0.6).abs() < 0.001);
        assert!((config.stability_threshold - 0.8).abs() < 0.001);
        assert!((config.max_depth_jump - 2.0).abs() < 0.001);
    }

    #[test]
    fn test_header_constants() {
        assert_eq!(DepthDataHeader::MAGIC, b"RLDP");
        assert_eq!(DepthDataHeader::SIZE, 16);
    }

    #[test]
    fn test_frame_index_size() {
        assert_eq!(DepthFrameIndex::SIZE, 12);
    }

    #[test]
    fn test_video_depth_analysis_default() {
        let analysis = VideoDepthAnalysis::default();
        assert!(analysis.frame_analyses.is_empty());
        assert!(!analysis.is_likely_real_scene);
        assert!(!analysis.is_valid());
    }

    #[test]
    fn test_video_depth_analysis_unavailable() {
        let analysis = VideoDepthAnalysis::unavailable();
        assert!(!analysis.is_valid());
    }

    #[test]
    fn test_video_depth_analysis_is_valid() {
        let mut analysis = VideoDepthAnalysis::default();
        assert!(!analysis.is_valid());

        analysis.frame_analyses.push(FrameDepthAnalysis {
            frame_index: 0,
            timestamp: 0.0,
            depth_histogram: vec![100; 10],
            motion_vector: None,
            local_consistency: 1.0,
        });
        assert!(analysis.is_valid());
    }

    #[test]
    fn test_frame_depth_analysis_serialization() {
        let frame = FrameDepthAnalysis {
            frame_index: 5,
            timestamp: 0.5,
            depth_histogram: vec![100, 200, 300, 400, 500, 400, 300, 200, 100, 50],
            motion_vector: Some((0.5, -0.3)),
            local_consistency: 0.95,
        };

        let json = serde_json::to_string(&frame).unwrap();
        assert!(json.contains("\"frame_index\":5"));
        assert!(json.contains("\"motion_vector\":[0.5,-0.3]"));

        let parsed: FrameDepthAnalysis = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.frame_index, 5);
        assert_eq!(parsed.motion_vector, Some((0.5, -0.3)));
    }

    #[test]
    fn test_video_depth_analysis_serialization() {
        let analysis = VideoDepthAnalysis {
            frame_analyses: vec![FrameDepthAnalysis {
                frame_index: 0,
                timestamp: 0.0,
                depth_histogram: vec![100; 10],
                motion_vector: None,
                local_consistency: 1.0,
            }],
            depth_consistency: 0.85,
            motion_coherence: 0.72,
            scene_stability: 0.95,
            is_likely_real_scene: true,
            suspicious_frames: vec![],
        };

        let json = serde_json::to_string(&analysis).unwrap();
        assert!(json.contains("\"depth_consistency\":0.85"));
        assert!(json.contains("\"is_likely_real_scene\":true"));

        let parsed: VideoDepthAnalysis = serde_json::from_str(&json).unwrap();
        assert!(parsed.is_likely_real_scene);
        assert_eq!(parsed.frame_analyses.len(), 1);
    }

    #[test]
    fn test_error_display() {
        let error = VideoDepthAnalysisError::InvalidMagic(*b"XXXX");
        assert!(error.to_string().contains("RLDP"));

        let error = VideoDepthAnalysisError::InsufficientFrames {
            count: 2,
            minimum: 5,
        };
        assert!(error.to_string().contains("2 frames"));
        assert!(error.to_string().contains("minimum: 5"));
    }
}
