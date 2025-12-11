# Story 9-7: Backend Multi-Signal Storage

Status: review

## Story

As a **backend service**,
I want **to receive, validate, and store multi-signal detection data from iOS capture uploads**,
So that **evidence packages include all detection signals for enhanced confidence calculation and transparency**.

## Acceptance Criteria

### AC 1: Database Schema Extension
**Given** the existing captures table
**When** the migration is applied
**Then**:
1. A new JSONB column `detection_results` stores multi-signal detection data
2. Column accepts null for captures without detection (backward compatible)
3. Index on `detection_results` using GIN for efficient queries on detection fields
4. Column comments document the expected JSON structure

### AC 2: Parse Detection JSON from Multipart Upload
**Given** an iOS capture upload with `detection` multipart field (Story 9-6)
**When** the backend parses the multipart form
**Then**:
1. Detects optional `detection` field (field name: "detection")
2. Parses JSON into DetectionResults struct
3. Validates required fields are present when detection data exists
4. Logs detection availability and method count for monitoring
5. Continues processing if detection field is absent (optional field)

### AC 3: DetectionResults Type Definition
**Given** the iOS DetectionResults payload format (Story 9-6)
**When** defining Rust types
**Then** types match iOS payload structure exactly:

**Main Container:**
```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DetectionResults {
    pub moire: Option<MoireAnalysisResult>,
    pub texture: Option<TextureClassificationResult>,
    pub artifacts: Option<ArtifactAnalysisResult>,
    pub aggregated_confidence: Option<AggregatedConfidenceResult>,
    pub cross_validation: Option<CrossValidationResult>,
    pub computed_at: DateTime<Utc>,
    pub total_processing_time_ms: i64,
}
```

**MoireAnalysisResult (matches iOS MoireAnalysisResult.swift):**
```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct MoireAnalysisResult {
    pub detected: bool,
    pub confidence: f32,
    pub peaks: Vec<FrequencyPeak>,
    pub screen_type: Option<ScreenType>,
    pub analysis_time_ms: i32,
    pub algorithm_version: String,
    pub computed_at: DateTime<Utc>,
    pub status: MoireAnalysisStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FrequencyPeak {
    pub frequency: f32,
    pub magnitude: f32,
    pub angle: f32,
    pub prominence: f32,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ScreenType { Lcd, Oled, HighRefresh, Unknown }

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MoireAnalysisStatus { Completed, Unavailable, Failed }
```

**AggregatedConfidenceResult (matches iOS AggregatedConfidenceResult.swift):**
```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct AggregatedConfidenceResult {
    pub overall_confidence: f32,
    pub confidence_level: AggregatedConfidenceLevel,
    pub method_breakdown: HashMap<String, MethodResult>,
    pub primary_signal_valid: bool,
    pub supporting_signals_agree: bool,
    pub flags: Vec<ConfidenceFlag>,
    pub analysis_time_ms: i64,
    pub computed_at: DateTime<Utc>,
    pub algorithm_version: String,
    pub status: AggregationStatus,
    pub cross_validation: Option<CrossValidationResult>,
    pub confidence_interval: Option<ConfidenceInterval>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MethodResult {
    pub available: bool,
    pub score: Option<f32>,
    pub weight: f32,
    pub contribution: f32,
    pub status: String,
}

/// iOS has 5 levels; backend has 4. Map very_high -> high for API responses.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AggregatedConfidenceLevel {
    VeryHigh, High, Medium, Low, Suspicious
}

impl AggregatedConfidenceLevel {
    /// Map to backend ConfidenceLevel (4 levels) for storage
    pub fn to_backend_level(&self) -> &'static str {
        match self {
            Self::VeryHigh | Self::High => "high",
            Self::Medium => "medium",
            Self::Low => "low",
            Self::Suspicious => "suspicious",
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConfidenceFlag {
    PrimarySignalFailed, ScreenDetected, PrintDetected, MethodsDisagree,
    PrimarySupportingDisagree, PartialAnalysis, LowConfidencePrimary,
    AmbiguousResults, ConsistencyAnomaly, TemporalInconsistency, HighUncertainty,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AggregationStatus { Success, Partial, Unavailable, Error }

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct ConfidenceInterval {
    pub lower_bound: f32,
    pub point_estimate: f32,
    pub upper_bound: f32,
}
```

**TextureClassificationResult (matches iOS TextureClassificationResult.swift):**
```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct TextureClassificationResult {
    pub classification: TextureType,
    pub confidence: f32,
    pub all_classifications: HashMap<String, f32>,
    pub is_likely_recaptured: bool,
    pub analysis_time_ms: i32,
    pub algorithm_version: String,
    pub computed_at: DateTime<Utc>,
    pub status: TextureClassificationStatus,
    pub unavailability_reason: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TextureType { RealScene, LcdScreen, OledScreen, PrintedPaper, Unknown }

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TextureClassificationStatus { Success, Unavailable, Error }
```

**ArtifactAnalysisResult (matches iOS ArtifactAnalysisResult.swift):**
```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct ArtifactAnalysisResult {
    pub pwm_flicker_detected: bool,
    pub pwm_confidence: f32,
    pub specular_pattern_detected: bool,
    pub specular_confidence: f32,
    pub halftone_detected: bool,
    pub halftone_confidence: f32,
    pub overall_confidence: f32,
    pub is_likely_artificial: bool,
    pub analysis_time_ms: i64,
    pub status: ArtifactAnalysisStatus,
    pub algorithm_version: String,
    pub computed_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ArtifactAnalysisStatus { Success, Unavailable, Error }
```

**CrossValidationResult (matches iOS CrossValidationResult.swift):**
```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct CrossValidationResult {
    pub validation_status: ValidationStatus,
    pub pairwise_consistencies: Vec<PairwiseConsistency>,
    pub temporal_consistency: Option<TemporalConsistency>,
    pub confidence_intervals: HashMap<String, ConfidenceInterval>,
    pub aggregated_interval: ConfidenceInterval,
    pub anomalies: Vec<AnomalyReport>,
    pub overall_penalty: f32,
    pub analysis_time_ms: i64,
    pub algorithm_version: String,
    pub computed_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ValidationStatus { Pass, Warn, Fail }

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct PairwiseConsistency {
    pub method_a: String,
    pub method_b: String,
    pub expected_relationship: ExpectedRelationship,
    pub actual_agreement: f32,
    pub anomaly_score: f32,
    pub is_anomaly: bool,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ExpectedRelationship { Positive, Negative, Neutral }

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct TemporalConsistency {
    pub frame_count: i32,
    pub stability_scores: HashMap<String, f32>,
    pub anomalies: Vec<TemporalAnomaly>,
    pub overall_stability: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct TemporalAnomaly {
    pub frame_index: i32,
    pub method: String,
    pub delta_score: f32,
    pub anomaly_type: TemporalAnomalyType,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TemporalAnomalyType { SuddenJump, Oscillation, Drift }

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct AnomalyReport {
    pub anomaly_type: AnomalyType,
    pub severity: AnomalySeverity,
    pub affected_methods: Vec<String>,
    pub details: String,
    pub confidence_impact: f32,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AnomalyType {
    ContradictorySignals, TooHighAgreement, IsolatedDisagreement,
    BoundaryCluster, CorrelationAnomaly,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AnomalySeverity { Low, Medium, High }
```

Uses snake_case serde to match iOS JSON encoding. DateTime fields use ISO 8601 format via chrono's default serde implementation.

### AC 4: Store Detection Results in Database
**Given** a capture upload with detection data
**When** inserting the capture record
**Then**:
1. Detection results serialized to JSONB and stored in `detection_results` column
2. Null stored when no detection data is provided
3. Transaction ensures atomicity with other capture fields
4. Query handles both captures with and without detection data

### AC 5: Include Detection in Evidence Package Response
**Given** a capture with stored detection results
**When** GET /api/v1/captures/{id} is called
**Then**:
1. Evidence package includes `detection` field when detection_results is not null
2. Response includes `detection_available: bool` flag
3. Web verification page can access detection data
4. Backward compatible: old captures return null/false for detection fields

### AC 6: Detection Summary in Metadata Response
**Given** detection results with aggregated confidence
**When** building capture metadata response
**Then** includes summary fields:
- `detection_confidence_level`: "high", "medium", "low", or "suspicious"
- `detection_primary_valid`: boolean (LiDAR check passed)
- `detection_signals_agree`: boolean (cross-validation agreement)
- `detection_method_count`: number of detection methods used

### AC 7: Validation of Detection Payload
**Given** a detection JSON payload
**When** validating the payload
**Then**:
1. Validates confidence values are 0.0-1.0 range
2. Validates timestamps are ISO 8601 format
3. Validates processing time is non-negative
4. Logs validation failures without rejecting upload (non-blocking)
5. Stores validated detection or null if validation fails

## Tasks / Subtasks

- [x] Task 1: Create database migration (AC: #1)
  - [x] Create migration file `20251206000001_add_detection_results.sql` (after 20251205)
  - [x] Add `detection_results` JSONB column to captures table
  - [x] Add GIN index for JSONB queries
  - [x] Add column comments for documentation
  - [ ] Run migration locally and update .sqlx cache

- [x] Task 2: Define DetectionResults types (AC: #3)
  - [x] Create `backend/src/types/detection.rs`
  - [x] Define MoireAnalysisResult struct (matches iOS)
  - [x] Define TextureClassificationResult struct
  - [x] Define ArtifactAnalysisResult struct
  - [x] Define AggregatedConfidenceResult struct
  - [x] Define CrossValidationResult struct
  - [x] Define DetectionResults container struct
  - [x] Add serde derives with snake_case rename
  - [x] Export from types/mod.rs

- [x] Task 3: Parse detection from multipart (AC: #2)
  - [x] Extend ParsedMultipart struct in captures.rs
  - [x] Add detection field parsing in parse_multipart()
  - [x] Handle optional detection field gracefully
  - [x] Add logging for detection presence/absence
  - [x] Validate detection JSON structure

- [x] Task 4: Update capture insert with detection (AC: #4)
  - [x] Add detection_results to InsertCaptureWithEvidenceParams
  - [x] Update insert_capture_with_evidence() SQL query
  - [x] Serialize DetectionResults to JSONB for storage
  - [x] Handle null detection_results

- [x] Task 5: Update capture model and queries (AC: #5)
  - [x] Add detection_results field to Capture struct
  - [x] Update SELECT queries in captures.rs
  - [x] Update CaptureDetailsResponse with detection fields

- [x] Task 6: Add detection to evidence package (AC: #5, #6)
  - [x] Add detection field to evidence package response
  - [x] Add detection summary fields to metadata response
  - [x] Ensure backward compatibility for old captures

- [x] Task 7: Implement validation (AC: #7)
  - [x] Add validate() method to DetectionResults
  - [x] Validate confidence ranges
  - [x] Validate timestamps
  - [x] Add validation logging

- [x] Task 8: Unit tests
  - [x] Test detection type serialization/deserialization
  - [x] Test multipart parsing with and without detection
  - [x] Test capture insert with detection data
  - [x] Test capture query with detection data
  - [x] Test validation edge cases

- [ ] Task 9: Integration tests
  - [ ] Test full upload flow with detection data
  - [ ] Test capture retrieval includes detection
  - [ ] Test backward compatibility with old captures

## Dev Notes

### Technical Approach

**Detection Payload Structure (from iOS):**
The iOS app sends detection results as a separate multipart field named "detection" containing JSON:

```json
{
  "moire": {
    "detected": false,
    "confidence": 0.0,
    "peaks": [],
    "screen_type": null,
    "analysis_time_ms": 45,
    "algorithm_version": "1.0"
  },
  "texture": {
    "classification": "natural",
    "confidence": 0.92,
    "top_predictions": [...],
    "analysis_time_ms": 23,
    "model_version": "1.0"
  },
  "artifacts": {
    "detected": false,
    "confidence": 0.0,
    "pwm_detected": false,
    "specular_detected": false,
    "halftone_detected": false,
    "analysis_time_ms": 15,
    "algorithm_version": "1.0"
  },
  "aggregated_confidence": {
    "confidence_level": "high",
    "overall_confidence": 0.95,
    "primary_signal_valid": true,
    "supporting_signals_agree": true,
    "lidar_depth": { "weight": 0.55, "score": 0.98, "status": "pass" },
    "moire": { "weight": 0.15, "score": 0.0, "status": "not_detected" },
    "texture": { "weight": 0.15, "score": 0.92, "status": "pass" },
    "artifact": { "weight": 0.15, "score": 0.0, "status": "not_detected" }
  },
  "cross_validation": {
    "agreement_status": "agree",
    "agreement_level": "strong",
    "confidence_boost": 0.05,
    "method_comparisons": [...]
  },
  "computed_at": "2025-12-11T10:30:00.123Z",
  "total_processing_time_ms": 85
}
```

**Database Storage:**
Store as JSONB for flexibility and query capability:
- GIN index enables queries on specific detection fields
- No schema rigidity - can add new detection methods without migration
- Efficient storage for sparse detection data

**Evidence Package Integration:**
Detection data becomes part of the evidence package for verification display:
- Primary signal (LiDAR depth) remains in existing depth_analysis
- Detection results provide SUPPORTING signals
- Cross-validation indicates agreement level

### Project Structure Notes

**New Files:**
- `backend/migrations/20251206000001_add_detection_results.sql` - Schema migration (after 20251205)
- `backend/src/types/detection.rs` - Detection type definitions

**Reuse Opportunity:**
- Reference `backend/src/types/hash_only.rs` for `AnalysisSource` enum (Server/Device)
- Can reuse pattern for serde attributes and validation

**Modified Files:**
- `backend/src/types/mod.rs` - Export detection types
- `backend/src/routes/captures.rs` - Parse/store detection data (update INSERT query inline)
- `backend/src/models/capture.rs` - Add detection_results field to Capture struct
- `backend/src/types/capture.rs` - Add detection to response types

**SQL Query Location:**
Update inline SQL in `captures.rs` for the INSERT statement. The existing pattern uses inline
queries with sqlx::query! macro. Keep consistent with existing approach rather than creating
separate query functions.

### Testing Standards

**Unit Tests:**
- Test serde serialization matches iOS JSON format
- Test validation accepts valid detection payloads
- Test validation rejects out-of-range values
- Test optional fields handled correctly

**Integration Tests:**
- Test upload with detection field succeeds
- Test upload without detection field succeeds (backward compatible)
- Test capture retrieval includes detection data
- Test old captures (no detection) still work

### References

- [Source: docs/epics.md#Epic-9-iOS-Defense-in-Depth] - FR69: Backend stores and validates multi-signal detection results
- [Source: docs/prd.md#Phase-1-iOS-Multi-Signal-Detection] - FR63-FR69 requirements
- [Source: ios/Rial/Models/DetectionResults.swift] - iOS payload structure
- [Source: ios/Rial/Core/Networking/UploadService.swift] - Detection multipart encoding
- [Source: backend/src/routes/captures.rs] - Existing upload handler
- [Source: backend/src/models/evidence.rs] - Evidence package structure
- [Source: backend/migrations/20251201000001_add_privacy_mode_fields.sql] - Migration pattern

### Related Stories

- Story 9-1: Moire Pattern Detection (iOS) - DONE
- Story 9-2: Texture Classification (iOS) - DONE
- Story 9-3: Artifact Detection (iOS) - DONE
- Story 9-4: Confidence Aggregation (iOS) - DONE
- Story 9-5: Cross-Validation Logic (iOS) - DONE
- Story 9-6: Detection Payload Integration (iOS) - DONE
- Story 9-8: Multi-Signal Integration Testing - BACKLOG (depends on this story)

### Security Considerations

**Validation is Non-Blocking:**
Detection data validation failures should NOT reject the upload:
- Detection is a SUPPORTING signal, not required
- Log validation failures for monitoring
- Store null if validation fails
- Continue with LiDAR-only evidence package

**Trust Model:**
Detection data comes from attested devices:
- Device attestation validates the source
- Detection algorithms run on-device (can't be spoofed without compromising device)
- Cross-validation between methods provides additional assurance

---

_Story created: 2025-12-11_
_Epic: 9 - iOS Defense-in-Depth_
_FR Coverage: FR69 (Backend stores and validates multi-signal detection results)_
_Depends on: Story 9-6 (iOS Detection Payload Integration)_
_Enables: Story 9-8 (Multi-Signal Integration Testing), Epic 11 (Detection Transparency)_

## Dev Agent Record

### Context Reference

N/A - Story created from epic requirements and existing code analysis.

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

N/A

### Completion Notes List

N/A - Story not yet implemented

### File List

**To Create:**
- `/Users/luca/dev/realitycam/backend/migrations/20251206000001_add_detection_results.sql`
- `/Users/luca/dev/realitycam/backend/src/types/detection.rs`

**To Modify:**
- `/Users/luca/dev/realitycam/backend/src/types/mod.rs`
- `/Users/luca/dev/realitycam/backend/src/routes/captures.rs`
- `/Users/luca/dev/realitycam/backend/src/models/capture.rs`
- `/Users/luca/dev/realitycam/backend/src/types/capture.rs`
