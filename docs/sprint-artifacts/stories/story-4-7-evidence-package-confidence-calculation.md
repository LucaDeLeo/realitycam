# Story 4.7: Evidence Package & Confidence Calculation

Status: done

## Story

As a **backend service processing uploaded captures**,
I want **to finalize evidence package aggregation and implement comprehensive confidence calculation**,
so that **I can combine hardware attestation, depth analysis, and metadata validation into a final confidence level that accurately reflects photo authenticity**.

## Acceptance Criteria

1. **AC-1: Evidence Package Aggregation**
   - Given all evidence checks have completed (hardware, depth, metadata)
   - When building the evidence package
   - Then all components are aggregated into EvidencePackage struct
   - And ProcessingInfo is added with timestamp, duration, and version
   - And package is serialized to JSONB for database storage

2. **AC-2: Confidence Level Calculation**
   - Given an evidence package with all checks completed
   - When calculating confidence level
   - Then apply rules:
     - SUSPICIOUS: Any check explicitly failed (hardware_attestation.status == fail OR depth_analysis.status == fail)
     - HIGH: Both hardware_attestation.status == pass AND depth_analysis.is_likely_real_scene == true
     - MEDIUM: Either hardware passes OR depth passes (but not both)
     - LOW: Both unavailable or both not passing but not failed

3. **AC-3: Processing Info Recording**
   - Given evidence pipeline has completed
   - When finalizing evidence package
   - Then record:
     - processed_at: ISO 8601 timestamp
     - processing_time_ms: Total time from upload receipt to completion
     - backend_version: From Cargo.toml version

4. **AC-4: Store Final Evidence Package**
   - Given evidence package is complete
   - When saving to database
   - Then serialize to JSONB and store in captures.evidence column
   - And update captures.confidence_level column
   - And update captures.status to "complete"

5. **AC-5: Complete Pipeline Timing**
   - Given evidence processing
   - When measuring performance
   - Then total processing time < 5 seconds
   - And timing is logged for monitoring

## Tasks / Subtasks

- [x] Task 1: Add ProcessingInfo to Evidence Package
  - [x] 1.1: Create ProcessingInfo struct in models/evidence.rs
  - [x] 1.2: Add processing field to EvidencePackage
  - [x] 1.3: Update EvidencePackage Default impl

- [x] Task 2: Implement Processing Info Recording
  - [x] 2.1: Track start time at upload receipt
  - [x] 2.2: Calculate processing_time_ms
  - [x] 2.3: Get backend_version from env or const
  - [x] 2.4: Set processed_at timestamp

- [x] Task 3: Verify Confidence Calculation Logic
  - [x] 3.1: Review existing calculate_confidence() method
  - [x] 3.2: Add tests for all confidence scenarios
  - [x] 3.3: Verify SUSPICIOUS takes precedence

- [x] Task 4: Update Capture Status to Complete
  - [x] 4.1: Update database insert to set status = "complete"
  - [x] 4.2: Verify evidence JSONB serialization includes all fields

- [x] Task 5: Add Performance Timing
  - [x] 5.1: Add timing instrumentation in captures.rs
  - [x] 5.2: Log total processing time
  - [x] 5.3: Add tests for processing info

## Dev Notes

### Confidence Calculation Matrix

| HW Attestation | Depth Analysis | Metadata Valid | Confidence |
|----------------|----------------|----------------|------------|
| pass | pass (real scene) | any | HIGH |
| pass | unavailable | any | MEDIUM |
| unavailable | pass (real scene) | any | MEDIUM |
| pass | fail (flat scene) | any | SUSPICIOUS |
| fail | any | any | SUSPICIOUS |
| unavailable | unavailable | any | LOW |
| unavailable | fail | any | SUSPICIOUS |

Note: Metadata validation contributes to evidence but does not directly affect confidence level (it's informational).

### Backend Version

Using const `BACKEND_VERSION = "0.1.0"` matching Cargo.toml. In production, this could be read from environment or build-time constant.

## Dev Agent Record

### Context Reference

N/A - Story created and implemented in single session

### Agent Model Used

- Claude Sonnet 4.5 (claude-sonnet-4-5-20250929)

### Completion Notes List

1. **ProcessingInfo added**: New struct added to evidence.rs with processed_at, processing_time_ms, and backend_version fields.

2. **Timing instrumentation**: Added timing start at upload handler entry, calculated elapsed time before evidence package creation.

3. **Backend version**: Using CARGO_PKG_VERSION env macro to get version from Cargo.toml at compile time.

4. **Status changed to complete**: Evidence pipeline now runs synchronously, so capture status is "complete" immediately (not "processing").

5. **Additional confidence tests**: Added tests for depth_fail_is_suspicious and depth_pass_hw_unavailable_is_medium scenarios.

### File List

**Modified:**
- `/Users/luca/dev/realitycam/backend/src/models/evidence.rs` - Added ProcessingInfo struct, updated EvidencePackage to include processing field, added confidence tests
- `/Users/luca/dev/realitycam/backend/src/models/mod.rs` - Exported ProcessingInfo
- `/Users/luca/dev/realitycam/backend/src/routes/captures.rs` - Added timing, processing info creation, updated status to "complete"

---

_Story created for BMAD Epic 4_
_Date: 2025-11-23_
_Epic: 4 - Upload, Processing & Evidence Generation_
