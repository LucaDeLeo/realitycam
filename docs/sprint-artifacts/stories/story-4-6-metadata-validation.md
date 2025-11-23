# Story 4.6: Metadata Validation

Status: done

## Story

As a **backend service processing uploaded captures**,
I want **to validate capture metadata including timestamp, location, and device info**,
so that **I can ensure the metadata is plausible and record validation results in the evidence package**.

## Acceptance Criteria

1. **AC-1: Timestamp Validation**
   - Given a capture with metadata containing captured_at timestamp
   - When metadata validation runs
   - Then timestamp is compared against server receipt time
   - And timestamp_valid = true if within 15 minutes of server time
   - And timestamp_delta_seconds is recorded (can be negative if in future)

2. **AC-2: Device Model Verification**
   - Given a capture with device_model in metadata
   - When metadata validation runs
   - Then device model is checked against iPhone Pro whitelist
   - And whitelist includes: iPhone 12 Pro, 12 Pro Max, 13 Pro, 13 Pro Max, 14 Pro, 14 Pro Max, 15 Pro, 15 Pro Max, 16 Pro, 16 Pro Max, 17 Pro, 17 Pro Max
   - And model_verified = true if model matches whitelist (case-insensitive, partial match)
   - And model_name is recorded in evidence

3. **AC-3: GPS Coordinate Validation**
   - Given a capture with location data
   - When metadata validation runs
   - Then latitude is validated: -90 <= lat <= 90
   - And longitude is validated: -180 <= lng <= 180
   - And location_available = true if valid coordinates provided
   - And location_available = false if no location or invalid

4. **AC-4: Resolution Validation**
   - Given depth map dimensions from metadata
   - When metadata validation runs
   - Then resolution is validated against known LiDAR resolutions
   - And valid resolutions include: 256x192, 320x240, 640x480
   - And resolution_valid = true if dimensions match known format
   - And allow tolerance for minor variations

5. **AC-5: MetadataEvidence Structure Update**
   - Given all metadata checks have completed
   - When building the MetadataEvidence struct
   - Then include:
     - timestamp_valid: bool
     - timestamp_delta_seconds: i64
     - model_verified: bool
     - model_name: String
     - resolution_valid: bool
     - location_available: bool
     - location_opted_out: bool (privacy setting)
   - And integrate with evidence package

6. **AC-6: Integration with Capture Upload**
   - Given a capture upload request
   - When evidence pipeline runs
   - Then metadata validation is called with capture metadata
   - And results are stored in evidence.metadata field
   - And validation is NON-BLOCKING (failures do not reject upload)

## Tasks / Subtasks

- [x] Task 1: Create Metadata Validation Service Module
  - [x] 1.1: Create `backend/src/services/metadata_validation.rs` module
  - [x] 1.2: Export module in `services/mod.rs`
  - [x] 1.3: Define validation constants (timestamp window, model whitelist, resolutions)

- [x] Task 2: Implement Timestamp Validation
  - [x] 2.1: Implement `validate_timestamp(captured_at: DateTime, server_time: DateTime) -> TimestampValidation`
  - [x] 2.2: Calculate delta in seconds (positive = past, negative = future)
  - [x] 2.3: Return validity based on 15-minute window
  - [x] 2.4: Add unit tests for edge cases

- [x] Task 3: Implement Device Model Verification
  - [x] 3.1: Define iPhone Pro whitelist as const array
  - [x] 3.2: Implement `verify_device_model(model: &str) -> ModelVerification`
  - [x] 3.3: Use case-insensitive partial matching
  - [x] 3.4: Add unit tests for various model string formats

- [x] Task 4: Implement Location Validation
  - [x] 4.1: Implement `validate_location(location: Option<&CaptureLocation>) -> LocationValidation`
  - [x] 4.2: Validate coordinate bounds
  - [x] 4.3: Handle missing location gracefully
  - [x] 4.4: Add unit tests for boundary conditions

- [x] Task 5: Implement Resolution Validation
  - [x] 5.1: Define valid LiDAR resolutions list
  - [x] 5.2: Implement `validate_resolution(width: u32, height: u32) -> bool`
  - [x] 5.3: Add tolerance for minor variations (+/- 10 pixels)
  - [x] 5.4: Add unit tests

- [x] Task 6: Update MetadataEvidence Struct
  - [x] 6.1: Add timestamp_delta_seconds field to MetadataEvidence
  - [x] 6.2: Add resolution_valid field
  - [x] 6.3: Add location_opted_out field
  - [x] 6.4: Update Default implementation

- [x] Task 7: Implement Main Validation Orchestrator
  - [x] 7.1: Implement `validate_metadata(metadata: &CaptureMetadataPayload) -> MetadataEvidence`
  - [x] 7.2: Orchestrate all validation checks
  - [x] 7.3: Add logging for validation results
  - [x] 7.4: Add unit tests for full validation flow

- [x] Task 8: Integrate with Upload Pipeline
  - [x] 8.1: Import metadata validation in captures.rs
  - [x] 8.2: Call validation after metadata parsing
  - [x] 8.3: Replace placeholder MetadataEvidence with actual validation
  - [x] 8.4: Ensure non-blocking behavior

- [x] Task 9: Add Comprehensive Tests
  - [x] 9.1: Test timestamp validation with various deltas
  - [x] 9.2: Test model verification with edge cases
  - [x] 9.3: Test location validation edge cases
  - [x] 9.4: Test full metadata validation integration

## Dev Notes

### Architecture Alignment

This story implements AC-4.6 from the Epic 4 Tech Spec:
> "EXIF timestamp extracted from photo using kamadak-exif. Timestamp valid if within 15 minutes of server receipt time. Device model verified against iPhone Pro whitelist (12-17 Pro/Pro Max). Resolution validated against known device capabilities. Location plausibility checked (lat -90 to 90, lng -180 to 180)."

**Note:** For MVP, we use the `captured_at` timestamp from metadata rather than EXIF extraction. EXIF parsing can be added in a future iteration.

### iPhone Pro Whitelist

Models with LiDAR:
- iPhone 12 Pro / Pro Max
- iPhone 13 Pro / Pro Max
- iPhone 14 Pro / Pro Max
- iPhone 15 Pro / Pro Max
- iPhone 16 Pro / Pro Max
- iPhone 17 Pro / Pro Max (future-proofing)

### Timestamp Validation Window

15 minutes (900 seconds) tolerance accounts for:
- Network latency
- Device clock drift
- Time zone edge cases
- Offline capture delays (though these may be flagged differently)

### Resolution Tolerance

LiDAR depth maps may have slight variations due to:
- Device-specific calibration
- SDK version differences
- Cropping during processing

Allow +/- 10 pixel tolerance on each dimension.

## Dev Agent Record

### Context Reference

N/A - Story created and implemented in single session

### Agent Model Used

- Claude Sonnet 4.5 (claude-sonnet-4-5-20250929)

### Completion Notes List

1. **Simplified timestamp validation**: Using captured_at from metadata JSON rather than EXIF extraction per MVP scope. EXIF parsing via kamadak-exif can be added in future iteration.

2. **Device model whitelist**: Implemented comprehensive iPhone Pro whitelist including generations 12-17. Uses flexible case-insensitive partial matching to handle various device string formats.

3. **Resolution tolerance**: Added +/- 10 pixel tolerance for LiDAR resolutions to handle device-specific variations.

4. **Non-blocking validation**: All validation failures are recorded in MetadataEvidence but do not reject uploads.

5. **MetadataEvidence expanded**: Added new fields timestamp_delta_seconds, model_name, resolution_valid, location_opted_out as specified in tech spec.

### File List

**Created:**
- `/Users/luca/dev/realitycam/backend/src/services/metadata_validation.rs` - Metadata validation service with 30+ unit tests

**Modified:**
- `/Users/luca/dev/realitycam/backend/src/models/evidence.rs` - Updated MetadataEvidence struct with new fields
- `/Users/luca/dev/realitycam/backend/src/services/mod.rs` - Added metadata_validation module export
- `/Users/luca/dev/realitycam/backend/src/routes/captures.rs` - Integrated metadata validation into upload pipeline

---

_Story created for BMAD Epic 4_
_Date: 2025-11-23_
_Epic: 4 - Upload, Processing & Evidence Generation_
