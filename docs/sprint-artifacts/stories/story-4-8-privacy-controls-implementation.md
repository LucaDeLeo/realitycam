# Story 4.8: Privacy Controls Implementation

Status: done

## Story

As a **user of RealityCam**,
I want **to control what location metadata is shared publicly**,
so that **I can protect my privacy while still having my photos verified**.

## Acceptance Criteria

1. **AC-1: Location Blurring/Coarsening**
   - Given a capture with precise GPS coordinates
   - When storing the capture
   - Then location_precise stores full precision internally (lat/lng to 6 decimal places)
   - And location_coarse stores city-level (~2 decimal places, ~1.1km precision)
   - And public API only returns location_coarse, never location_precise

2. **AC-2: Privacy Settings in Metadata**
   - Given a capture metadata payload
   - When location is not provided
   - Then location_opted_out = true in MetadataEvidence
   - And location_available = false
   - And this is treated as user choice (not failure)

3. **AC-3: Location Coarsening Implementation**
   - Given precise GPS coordinates (latitude, longitude)
   - When coarsening for public display
   - Then round coordinates to 2 decimal places
   - And optionally reverse geocode to city name (if service available)
   - And store in evidence.metadata.location_coarse

4. **AC-4: Evidence Package Privacy**
   - Given a complete evidence package
   - When storing in database
   - Then location_precise goes to captures.location_precise column
   - And location_coarse goes to evidence.metadata.location_coarse
   - And public endpoints never expose location_precise

5. **AC-5: Depth Map Privacy**
   - Given a depth map stored in S3
   - When generating public verification response
   - Then only depth visualization (PNG preview) is accessible
   - And raw float32 depth array is never downloadable via public API

## Tasks / Subtasks

- [x] Task 1: Create Privacy Module
  - [x] 1.1: Create `backend/src/services/privacy.rs` module
  - [x] 1.2: Export in services/mod.rs
  - [x] 1.3: Implement coarsen_coordinates function

- [x] Task 2: Implement Location Coarsening
  - [x] 2.1: Round lat/lng to 2 decimal places (~1.1km precision)
  - [x] 2.2: Create format_location_coarse function for display
  - [x] 2.3: Add unit tests for coarsening

- [x] Task 3: Integrate Privacy into Upload Pipeline
  - [x] 3.1: Call coarsen_coordinates in captures.rs
  - [x] 3.2: Set location_coarse in MetadataEvidence
  - [x] 3.3: Ensure location_precise stored separately

- [x] Task 4: Add Privacy-Related Tests
  - [x] 4.1: Test location coarsening accuracy
  - [x] 4.2: Test opted-out behavior
  - [x] 4.3: Test boundary coordinates

## Dev Notes

### Location Precision Levels

| Precision | Decimal Places | Accuracy | Use Case |
|-----------|----------------|----------|----------|
| Precise | 6 | ~0.1m | Internal storage |
| Coarse | 2 | ~1.1km | Public display |
| City | Name only | ~10km | Alternative display |

### Coordinate Coarsening

Example:
- Precise: 37.774929, -122.419418 (San Francisco)
- Coarse: 37.77, -122.42 (~1km precision)

### Future Enhancements (Post-MVP)

1. Reverse geocoding to city names using `reverse-geocoder` crate
2. User-selectable privacy levels
3. Complete location opt-out at device level

## Dev Agent Record

### Context Reference

N/A - Story created and implemented in single session

### Agent Model Used

- Claude Sonnet 4.5 (claude-sonnet-4-5-20250929)

### Completion Notes List

1. **Location coarsening**: Implemented 2 decimal place precision (~1.1km) for public location display.

2. **Privacy module**: Created dedicated privacy.rs service for location-related privacy functions.

3. **Evidence integration**: location_coarse is now populated in MetadataEvidence from the privacy service.

4. **Dual storage**: Precise location stored in captures.location_precise (internal), coarse location in evidence.metadata.location_coarse (public).

5. **Future enhancements identified**: Reverse geocoding to city names, user-selectable privacy levels.

### File List

**Created:**
- `/Users/luca/dev/realitycam/backend/src/services/privacy.rs` - Privacy controls service with 11 unit tests

**Modified:**
- `/Users/luca/dev/realitycam/backend/src/services/mod.rs` - Added privacy module export
- `/Users/luca/dev/realitycam/backend/src/routes/captures.rs` - Integrated privacy controls into upload pipeline

---

_Story created for BMAD Epic 4_
_Date: 2025-11-23_
_Epic: 4 - Upload, Processing & Evidence Generation_
