# Story 7-9-video-depth-analysis-service: Video Depth Analysis Service

## Story Overview
- **Epic:** 7 - Video Capture with LiDAR Depth
- **Story ID:** 7-9-video-depth-analysis-service
- **Priority:** P0
- **Estimated Effort:** M
- **Dependencies:** Story 7-8-video-upload-endpoint (provides uploaded depth_data), Story 4-5-lidar-depth-analysis-service (photo depth patterns)

## User Story

As a **backend verification system**,
I want **to analyze temporal depth consistency across video keyframes**,
So that **I can detect manipulation attempts that single-frame analysis would miss**.

## Story Context

This story implements temporal depth analysis for video captures on the backend. Unlike photo captures (Story 4-5) which analyze a single depth frame, video analysis examines consistency across 10fps depth keyframes to detect:

1. **Splice attacks:** Footage from different scenes stitched together
2. **Frame insertion:** Foreign frames inserted into genuine recording
3. **Temporal discontinuities:** Impossible depth jumps between frames
4. **Motion inconsistencies:** Depth motion that doesn't match RGB motion

The service processes the uploaded `depth_data` blob (gzipped depth keyframes from Story 7-8) and produces a `VideoDepthAnalysis` result that feeds into the evidence package (Story 7-11).

### Key Design Decisions

1. **1fps sampling:** Instead of analyzing all 150 keyframes (10fps x 15s), sample at 1fps (15 frames) for efficiency while maintaining detection capability.

2. **Three-metric approach:**
   - `depth_consistency`: How stable is depth across frames? (0-1)
   - `motion_coherence`: Does depth motion match RGB motion direction? (0-1)
   - `scene_stability`: Are there impossible depth jumps? (0-1)

3. **Suspicious frame flagging:** Individual frames with anomalies are flagged for human review.

4. **Graceful degradation:** If analysis fails, capture still processes with reduced confidence rather than failing entirely.

---

## Acceptance Criteria

### AC-7.9.1: Depth Data Decompression
**Given** uploaded `depth_data` blob from Story 7-8
**When** depth analysis is initiated
**Then**:
1. Gzipped blob is decompressed
2. Float32 depth arrays extracted per keyframe
3. Keyframe index and timestamps preserved
4. Invalid/corrupt data detected and handled gracefully

### AC-7.9.2: Depth Consistency Analysis
**Given** extracted depth keyframes (10fps, up to 150 frames)
**When** depth_consistency is computed
**Then**:
1. Sample frames at 1fps (every 10th keyframe)
2. Compare depth histograms between consecutive samples
3. Score 0-1 where 1 = perfectly consistent scene
4. Threshold: >= 0.7 considered consistent

### AC-7.9.3: Motion Coherence Analysis
**Given** consecutive depth keyframes
**When** motion_coherence is computed
**Then**:
1. Compute optical flow on depth frames
2. Detect primary motion direction per frame
3. Score 0-1 where 1 = motion coherent with scene
4. Threshold: >= 0.6 considered coherent

### AC-7.9.4: Scene Stability Analysis
**Given** depth keyframes across video duration
**When** scene_stability is computed
**Then**:
1. Detect large depth discontinuities (>2m jump in single frame)
2. Identify impossible object appearances/disappearances
3. Score 0-1 where 1 = stable scene
4. Threshold: >= 0.8 considered stable

### AC-7.9.5: Suspicious Frame Detection
**Given** completed temporal analysis
**When** results are aggregated
**Then**:
1. Frames with depth_jump > 2m flagged
2. Frames with motion_incoherence flagged
3. Frame indices stored in `suspicious_frames` array
4. `is_likely_real_scene` boolean computed from aggregate scores

### AC-7.9.6: VideoDepthAnalysis Output
**Given** all analysis steps complete
**When** results are assembled
**Then**:
```json
{
  "frame_analyses": [
    { "frame_index": 0, "timestamp": 0.0, "depth_histogram": [...], "motion_vector": [...] },
    { "frame_index": 10, "timestamp": 1.0, ... }
  ],
  "depth_consistency": 0.85,
  "motion_coherence": 0.72,
  "scene_stability": 0.95,
  "is_likely_real_scene": true,
  "suspicious_frames": []
}
```

### AC-7.9.7: Integration with Capture Processing
**Given** video capture uploaded (Story 7-8)
**When** backend processes capture
**Then**:
1. Depth analysis runs as part of processing pipeline
2. Results stored in capture record
3. Analysis failures don't block capture processing
4. Failures logged with error details

---

## Technical Requirements

### Video Depth Analysis Service

```rust
// services/video_depth_analysis.rs

/// Analyzes temporal depth consistency across video keyframes.
///
/// Examines 10fps depth keyframes to detect manipulation attempts:
/// - Splice attacks (footage from different scenes)
/// - Frame insertion (foreign frames in genuine recording)
/// - Temporal discontinuities (impossible depth jumps)
/// - Motion inconsistencies (depth vs RGB motion mismatch)
pub struct VideoDepthAnalysisService {
    config: VideoDepthAnalysisConfig,
}

impl VideoDepthAnalysisService {
    /// Analyze depth keyframes from uploaded video capture
    pub async fn analyze(&self, depth_data: &[u8]) -> Result<VideoDepthAnalysis, AnalysisError>;

    /// Decompress and parse depth keyframes from gzipped blob
    fn decompress_depth_data(&self, data: &[u8]) -> Result<Vec<DepthKeyframe>, AnalysisError>;

    /// Compute depth consistency score across sampled frames
    fn compute_depth_consistency(&self, frames: &[DepthKeyframe]) -> f32;

    /// Compute motion coherence score using optical flow
    fn compute_motion_coherence(&self, frames: &[DepthKeyframe]) -> f32;

    /// Compute scene stability score detecting impossible jumps
    fn compute_scene_stability(&self, frames: &[DepthKeyframe]) -> f32;

    /// Identify frames with anomalies
    fn detect_suspicious_frames(&self, frames: &[DepthKeyframe]) -> Vec<u32>;
}
```

### Data Structures

```rust
// types/video_depth_analysis.rs

/// Configuration for video depth analysis
#[derive(Debug, Clone)]
pub struct VideoDepthAnalysisConfig {
    /// Sample rate for analysis (default: 1fps = every 10th keyframe)
    pub sample_rate: u32,
    /// Threshold for depth consistency (default: 0.7)
    pub consistency_threshold: f32,
    /// Threshold for motion coherence (default: 0.6)
    pub coherence_threshold: f32,
    /// Threshold for scene stability (default: 0.8)
    pub stability_threshold: f32,
    /// Maximum depth jump before flagging (meters)
    pub max_depth_jump: f32,
}

impl Default for VideoDepthAnalysisConfig {
    fn default() -> Self {
        Self {
            sample_rate: 10,           // 1fps from 10fps keyframes
            consistency_threshold: 0.7,
            coherence_threshold: 0.6,
            stability_threshold: 0.8,
            max_depth_jump: 2.0,       // 2 meters
        }
    }
}

/// A single depth keyframe extracted from video
#[derive(Debug, Clone)]
pub struct DepthKeyframe {
    /// Keyframe index (0-based)
    pub index: u32,
    /// Timestamp in video (seconds)
    pub timestamp: f64,
    /// Depth data as 256x192 Float32 array
    pub depth_data: Vec<f32>,
    /// Resolution
    pub width: u32,
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
    pub depth_histogram: [u32; 10],
    /// Primary motion vector (dx, dy) from optical flow
    pub motion_vector: Option<(f32, f32)>,
    /// Local depth consistency with previous frame
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

#[derive(Debug, thiserror::Error)]
pub enum AnalysisError {
    #[error("Failed to decompress depth data: {0}")]
    DecompressionError(String),

    #[error("Invalid depth data format: {0}")]
    InvalidFormat(String),

    #[error("Insufficient frames for analysis: {0}")]
    InsufficientFrames(usize),

    #[error("Analysis computation failed: {0}")]
    ComputationError(String),
}
```

### Depth Data Format

The uploaded `depth_data` blob format (from iOS):
```
Header (16 bytes):
  - magic: "RLDP" (4 bytes)
  - version: u32 (4 bytes)
  - frame_count: u32 (4 bytes)
  - resolution: u16 x u16 (4 bytes)

Frame Index (frame_count * 12 bytes):
  - timestamp: f64 (8 bytes)
  - offset: u32 (4 bytes)

Frame Data (variable):
  - Each frame: width * height * 4 bytes (Float32)

All data is gzipped as a single blob.
```

### Integration Points

1. **Story 7-8 (Upload):** Receives `depth_data` blob from S3 after upload
2. **Story 7-11 (Evidence):** VideoDepthAnalysis feeds into evidence package
3. **Story 4-5 (Photo Depth):** Shares histogram computation and analysis patterns

---

## Implementation Tasks

### Task 1: Create Video Depth Analysis Types
**File:** `backend/src/types/video_depth_analysis.rs`

Define analysis types:
- [ ] Create `VideoDepthAnalysisConfig` struct with defaults
- [ ] Create `DepthKeyframe` struct for parsed frames
- [ ] Create `FrameDepthAnalysis` struct for per-frame results
- [ ] Create `VideoDepthAnalysis` struct for complete results
- [ ] Create `AnalysisError` enum with thiserror derives
- [ ] Add serde Serialize/Deserialize for JSON output

### Task 2: Implement Depth Data Decompression
**File:** `backend/src/services/video_depth_analysis.rs`

Implement decompression:
- [ ] Add `flate2` dependency for gzip decompression
- [ ] Parse header (magic, version, frame_count, resolution)
- [ ] Parse frame index (timestamps, offsets)
- [ ] Extract Float32 depth arrays per frame
- [ ] Validate data integrity
- [ ] Handle corrupt/truncated data gracefully

### Task 3: Implement Depth Consistency Analysis
**File:** `backend/src/services/video_depth_analysis.rs`

Compute depth consistency:
- [ ] Sample frames at configured rate (1fps default)
- [ ] Compute depth histogram (10 bins, 0-10m range)
- [ ] Compare histograms using chi-squared distance
- [ ] Normalize to 0-1 score
- [ ] Handle edge cases (single frame, all invalid depth)

### Task 4: Implement Motion Coherence Analysis
**File:** `backend/src/services/video_depth_analysis.rs`

Compute motion coherence:
- [ ] Compute simple optical flow between consecutive sampled frames
- [ ] Detect primary motion direction (dx, dy)
- [ ] Check motion consistency across sequence
- [ ] Score based on motion smoothness
- [ ] Handle static scenes (no motion = coherent)

### Task 5: Implement Scene Stability Analysis
**File:** `backend/src/services/video_depth_analysis.rs`

Compute scene stability:
- [ ] Compute per-pixel depth differences between frames
- [ ] Detect large jumps (> max_depth_jump threshold)
- [ ] Count percentage of stable pixels
- [ ] Score based on stability percentage
- [ ] Identify specific frames with jumps

### Task 6: Implement Suspicious Frame Detection
**File:** `backend/src/services/video_depth_analysis.rs`

Detect anomalies:
- [ ] Aggregate frame-level metrics
- [ ] Flag frames exceeding thresholds
- [ ] Compute `is_likely_real_scene` from aggregate scores
- [ ] Store suspicious frame indices

### Task 7: Create Video Depth Analysis Service
**File:** `backend/src/services/video_depth_analysis.rs`

Assemble service:
- [ ] Create `VideoDepthAnalysisService` struct
- [ ] Implement `new()` with default config
- [ ] Implement `with_config()` for custom config
- [ ] Implement `analyze()` orchestrating all steps
- [ ] Add tracing spans for observability
- [ ] Handle errors gracefully with fallbacks

### Task 8: Register Service in AppState
**File:** `backend/src/lib.rs` or `backend/src/services/mod.rs`

Wire up service:
- [ ] Export `video_depth_analysis` module
- [ ] Add service to AppState or create on demand
- [ ] Add configuration to environment/config

### Task 9: Integrate with Capture Processing
**File:** `backend/src/routes/captures_video.rs` or new processing module

Integrate analysis:
- [ ] Call analysis after upload completes
- [ ] Store results in capture record
- [ ] Handle analysis failures gracefully
- [ ] Add tracing for pipeline visibility

---

## Test Requirements

### Unit Tests
**File:** `backend/src/services/video_depth_analysis_tests.rs`

- [ ] Test depth data decompression with valid blob
- [ ] Test decompression failure with corrupt data
- [ ] Test decompression failure with wrong magic bytes
- [ ] Test histogram computation correctness
- [ ] Test chi-squared distance computation
- [ ] Test depth_consistency with identical frames (should be 1.0)
- [ ] Test depth_consistency with random frames (should be low)
- [ ] Test motion_coherence with static scene (should be 1.0)
- [ ] Test scene_stability with stable scene (should be 1.0)
- [ ] Test scene_stability detects large jump
- [ ] Test suspicious frame detection flags correct frames
- [ ] Test is_likely_real_scene threshold logic
- [ ] Test with minimum frames (edge case)
- [ ] Test with maximum frames (performance)

### Integration Tests
**File:** `backend/tests/video_depth_analysis_integration.rs`

- [ ] Test full analysis pipeline with fixture data
- [ ] Test analysis with real depth data sample
- [ ] Test analysis results JSON serialization
- [ ] Test service configuration overrides
- [ ] Test error handling with various invalid inputs

### Test Fixtures

Create test fixtures in `backend/tests/fixtures/`:
- [ ] `valid_depth_data.gz` - 15 frames of consistent depth
- [ ] `splice_attack.gz` - Frames from two different scenes
- [ ] `frame_jump.gz` - Frame with 3m depth discontinuity
- [ ] `corrupt_depth.gz` - Invalid/truncated data
- [ ] `minimal_depth.gz` - Single frame (edge case)

---

## Definition of Done

- [ ] All acceptance criteria met (AC-7.9.1 through AC-7.9.7)
- [ ] VideoDepthAnalysisService implemented with all analysis methods
- [ ] Depth data decompression working with iOS format
- [ ] Three metrics computed correctly (consistency, coherence, stability)
- [ ] Suspicious frame detection working
- [ ] Unit tests passing with >= 85% coverage
- [ ] Integration tests passing with fixture data
- [ ] Performance acceptable (< 2s for 150 keyframes)
- [ ] No new lint errors (Clippy)
- [ ] Tracing/logging for observability
- [ ] Ready for Story 7-11 (Evidence Package) integration

---

## Technical Notes

### Why Sampling at 1fps?

Analyzing all 150 keyframes (10fps x 15s) is computationally expensive:
- 150 histogram comparisons
- 149 optical flow computations
- ~3 seconds processing time

Sampling at 1fps (15 frames) provides:
- Sufficient temporal coverage (1 frame/second)
- 10x faster processing (~300ms)
- Still detects most manipulation attempts

Splice attacks typically occur at edit points visible at 1fps sampling.

### Depth Histogram Binning

10 bins from 0-10 meters:
- Bin 0: 0-1m (very close)
- Bin 1: 1-2m (close)
- Bin 2: 2-3m (near)
- ...
- Bin 9: 9-10m+ (far)

Histogram comparison using chi-squared distance:
```
χ² = Σ (O_i - E_i)² / E_i
```

### Motion Coherence Computation

Simple optical flow approach:
1. Downsample depth frames to 64x48
2. Compute block-wise correlation between frames
3. Find peak correlation offset (motion vector)
4. Check motion vector consistency across sequence

Not using full RGB optical flow to:
- Keep backend simpler (no video frame extraction)
- Depth-only analysis sufficient for basic coherence

### Performance Considerations

Target: < 2 seconds for 150 keyframes

Optimizations:
- Sample at 1fps (10x reduction)
- Downsampled depth for motion analysis
- Parallel histogram computation with rayon
- Early exit on obvious failures

---

## Source Document References

- **Epic:** docs/epics.md - Story 7.9: Video Depth Analysis Service
- **Tech Spec:** docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-7.md
  - Section: Data Models > VideoDepthAnalysis
  - Section: AC-7.9 (Temporal Depth Analysis)
  - Section: Services > video_depth_analysis.rs
- **Architecture:** docs/architecture.md - Backend services patterns
- **Previous Stories:**
  - docs/sprint-artifacts/stories/7-8-video-upload-endpoint.md (depth_data input)
  - docs/sprint-artifacts/stories/4-5-lidar-depth-analysis-service.md (photo depth patterns)

---

## FR Coverage

This story implements:
- **FR53:** Backend performs temporal depth analysis for video manipulation detection

This story enables:
- **FR52:** Evidence package includes depth analysis results (Story 7-11)

---

_Story created: 2025-11-27_
_FR Coverage: FR53 (Video temporal depth analysis)_

---

## Dev Agent Record

### Status
**Status:** draft

### Context Reference
N/A (not yet created)

### File List
**To Be Created:**
- `backend/src/types/video_depth_analysis.rs` - Analysis types and config
- `backend/src/services/video_depth_analysis.rs` - Analysis service implementation
- `backend/tests/video_depth_analysis_integration.rs` - Integration tests
- `backend/tests/fixtures/valid_depth_data.gz` - Test fixture
- `backend/tests/fixtures/splice_attack.gz` - Test fixture
- `backend/tests/fixtures/frame_jump.gz` - Test fixture
- `backend/tests/fixtures/corrupt_depth.gz` - Test fixture

**To Be Modified:**
- `backend/src/types/mod.rs` - Export video_depth_analysis types
- `backend/src/services/mod.rs` - Export video_depth_analysis service
- `backend/Cargo.toml` - Add flate2 dependency (if not present)

### Completion Notes
N/A (story not yet implemented)
