# Story 3.5: Local Processing Pipeline

Status: review

## Story

As a **mobile app user with an iPhone Pro device**,
I want **captured photos to be processed locally with compressed depth data, computed hashes, and assembled metadata**,
so that **the capture is ready for upload with optimized size and complete cryptographic verification data**.

## Acceptance Criteria

1. **AC-1: ProcessedCapture Type Definition**
   - Given the shared types package
   - When processed capture types are defined
   - Then a `ProcessedCapture` interface exists with:
     - `id: string` - Capture UUID
     - `photoUri: string` - Local file URI to captured JPEG
     - `photoHash: string` - SHA-256 base64 of photo bytes
     - `compressedDepthMap: string` - Base64-encoded gzipped depth map
     - `depthDimensions: { width: number; height: number }` - Depth map dimensions
     - `metadata: CaptureMetadata` - Assembled metadata
     - `assertion?: string` - Base64 device assertion (if available)
     - `status: CaptureStatus` - Processing lifecycle status
     - `createdAt: string` - ISO timestamp

2. **AC-2: CaptureMetadata Type Definition**
   - Given the shared types package
   - When metadata types are defined
   - Then a `CaptureMetadata` interface exists with:
     - `captured_at: string` - ISO timestamp
     - `device_model: string` - Device model string
     - `photo_hash: string` - SHA-256 base64 of photo
     - `depth_map_dimensions: { width: number; height: number }`
     - `location?: CaptureLocation` - Optional GPS data
     - `assertion?: string` - Base64 per-capture assertion

3. **AC-3: CaptureStatus Type**
   - Given the capture lifecycle
   - When status values are defined
   - Then `CaptureStatus` type includes:
     - `'capturing'` - Photo + depth being taken
     - `'processing'` - Local processing (hash, compress)
     - `'ready'` - Ready for upload
     - `'uploading'` - Upload in progress (Epic 4)
     - `'completed'` - Upload successful
     - `'failed'` - Upload failed

4. **AC-4: useCaptureProcessing Hook API**
   - Given the capture flow uses the hook
   - When the `useCaptureProcessing` hook is used
   - Then it provides:
     - `processCapture(raw: RawCapture): Promise<ProcessedCapture>` - Process raw capture
     - `isProcessing: boolean` - True during processing
     - `error: ProcessingError | null` - Error from last operation
     - `clearError: () => void` - Clear error state

5. **AC-5: Gzip Depth Map Compression**
   - Given a depth frame with Float32Array data
   - When `processCapture()` is called
   - Then depth map is base64-decoded from DepthFrame.depthMap
   - And decoded bytes are gzip compressed using pako
   - And compressed result is base64-encoded for storage
   - And original size ~192KB (256*192*4 bytes)
   - And compressed size typically ~100-150KB

6. **AC-6: SHA-256 Photo Hash**
   - Given a captured photo at photoUri
   - When `processCapture()` is called
   - Then photo bytes are read from file URI
   - And SHA-256 hash is computed using expo-crypto
   - And hash is base64 encoded
   - And computation completes in < 500ms for typical photo

7. **AC-7: Metadata Assembly**
   - Given photo, depth, location, and assertion data
   - When metadata is assembled
   - Then `CaptureMetadata` includes all fields from RawCapture
   - And device_model is obtained from device capabilities
   - And assertion is included if available in RawCapture

8. **AC-8: ProcessedCapture Construction**
   - Given processing completes successfully
   - When ProcessedCapture is returned
   - Then all fields are populated from processed data
   - And status is set to 'ready'
   - And createdAt matches capturedAt from RawCapture

## Tasks / Subtasks

- [x] Task 1: Create Processing Types (AC: 1, 2, 3)
  - [x] 1.1: Add `CaptureStatus` type to `packages/shared/src/types/capture.ts`
  - [x] 1.2: Add `CaptureMetadata` interface
  - [x] 1.3: Add `ProcessedCapture` interface
  - [x] 1.4: Add `ProcessingErrorCode` type
  - [x] 1.5: Add `ProcessingError` interface
  - [x] 1.6: Export new types from `packages/shared/src/index.ts`

- [x] Task 2: Create useCaptureProcessing Hook (AC: 4, 5, 6, 7, 8)
  - [x] 2.1: Create `apps/mobile/hooks/useCaptureProcessing.ts`
  - [x] 2.2: Import pako for gzip compression
  - [x] 2.3: Import expo-crypto for SHA-256 hashing
  - [x] 2.4: Import expo-file-system for reading photo bytes
  - [x] 2.5: Implement `compressDepthMap()` helper function
  - [x] 2.6: Implement `computePhotoHash()` helper function (inline in processCapture)
  - [x] 2.7: Implement `assembleMetadata()` helper function (inline in processCapture)
  - [x] 2.8: Implement `processCapture()` main function
  - [x] 2.9: Add processing state management (isProcessing, error)
  - [x] 2.10: Return ProcessedCapture with status 'ready'

- [x] Task 3: Export Hook from Hooks Index (AC: 4)
  - [x] 3.1: Add `useCaptureProcessing` export to `apps/mobile/hooks/index.ts`

- [x] Task 4: Verify pako Dependency (AC: 5)
  - [x] 4.1: Check pako is installed in mobile package
  - [x] 4.2: Install pako if missing (installed pako and @types/pako)

## Dev Notes

### Architecture Alignment

This story implements AC-3.7, AC-3.8, AC-3.9 from Epic 3 Tech Spec. It builds upon:
- Story 3-2's `RawCapture` type with photo and depth data
- Story 3-3's `CaptureLocation` for optional location
- Story 3-4's `CaptureAssertion` for optional attestation

**Key alignment points:**
- **pako (Tech Spec):** Gzip compression for depth map
- **expo-crypto (Tech Spec):** SHA-256 hashing
- **Processing pipeline:** Runs after capture, before upload

### Processing Flow

Per Epic 3 Tech Spec section "Local Processing Pipeline":

```typescript
// 1. Compress depth map with gzip
const depthMapBytes = base64ToBytes(raw.depthFrame.depthMap);
const compressedDepthMap = pako.gzip(depthMapBytes);
const compressedBase64 = bytesToBase64(compressedDepthMap);

// 2. Compute SHA-256 hash of photo
const photoBase64 = await FileSystem.readAsStringAsync(raw.photoUri, {
  encoding: 'base64',
});
const photoHash = await Crypto.digestStringAsync(
  Crypto.CryptoDigestAlgorithm.SHA256,
  photoBase64,
  { encoding: Crypto.CryptoEncoding.BASE64 }
);

// 3. Assemble metadata
const metadata: CaptureMetadata = {
  captured_at: raw.capturedAt,
  device_model: deviceModel,
  photo_hash: photoHash,
  depth_map_dimensions: {
    width: raw.depthFrame.width,
    height: raw.depthFrame.height,
  },
  location: raw.location,
  assertion: raw.assertion?.assertion,
};
```

### Performance Targets

Per Epic 3 Tech Spec NFRs:
- SHA-256 hash computation: < 500ms for ~3MB JPEG
- Depth map compression: < 500ms for 256x192 float32
- Total local processing: < 2 seconds

### References

- [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-3.md#AC-3.7]
- [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-3.md#AC-3.8]
- [Source: docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-3.md#AC-3.9]
- [Source: docs/sprint-artifacts/stories/3-2-photo-capture-depth-map.md]
- [Source: docs/sprint-artifacts/stories/3-4-capture-attestation-signature.md]

## Dev Agent Record

### Context Reference

Story file dev notes used as context

### Agent Model Used

claude-sonnet-4-5-20250929

### Debug Log References

N/A

### Completion Notes List

#### Implementation Summary

Implemented local processing pipeline with gzip compression of depth maps and SHA-256 hashing of photos. The `useCaptureProcessing` hook processes raw captures into upload-ready packages with compressed depth data and assembled metadata.

#### Key Implementation Decisions

1. **Base64 Encoding**: Depth maps are stored as base64-encoded gzip-compressed data for easy serialization and transport.

2. **Helper Functions**: `base64ToBytes` and `bytesToBase64` helper functions handle conversion between base64 strings and Uint8Array for pako compression.

3. **Inline Processing**: Photo hash computation and metadata assembly are done inline in `processCapture()` rather than separate functions for simplicity.

4. **Error Classification**: Processing errors are classified by type (HASH_FAILED, COMPRESSION_FAILED, FILE_READ_FAILED, UNKNOWN) for debugging.

5. **Device Model**: Device model is obtained from deviceStore capabilities, with fallback to "Unknown iPhone" if unavailable.

#### Acceptance Criteria Status

- AC-1 (ProcessedCapture Type Definition): SATISFIED - Interface at `capture.ts:259-281`
- AC-2 (CaptureMetadata Type Definition): SATISFIED - Interface at `capture.ts:237-253`
- AC-3 (CaptureStatus Type): SATISFIED - Type at `capture.ts:225-231`
- AC-4 (useCaptureProcessing Hook API): SATISFIED - Hook at `useCaptureProcessing.ts:89-220`
- AC-5 (Gzip Depth Map Compression): SATISFIED - `compressDepthMap()` at `useCaptureProcessing.ts:64-74`
- AC-6 (SHA-256 Photo Hash): SATISFIED - Hash computation at `useCaptureProcessing.ts:117-130`
- AC-7 (Metadata Assembly): SATISFIED - Metadata assembly at `useCaptureProcessing.ts:160-172`
- AC-8 (ProcessedCapture Construction): SATISFIED - Construction at `useCaptureProcessing.ts:179-195`

#### Technical Debt / Follow-ups

- Testing tasks deferred to testing sprint
- Consider adding progress callback for large photo processing
- Performance benchmarking on device needed for NFR validation

### File List

#### Created

- `/Users/luca/dev/realitycam/apps/mobile/hooks/useCaptureProcessing.ts` - New hook for local processing pipeline
- `/Users/luca/dev/realitycam/docs/sprint-artifacts/stories/3-5-local-processing-pipeline.md` - Story file

#### Modified

- `/Users/luca/dev/realitycam/packages/shared/src/types/capture.ts` - Added CaptureStatus, CaptureMetadata, ProcessedCapture, ProcessingErrorCode, ProcessingError types
- `/Users/luca/dev/realitycam/packages/shared/src/index.ts` - Exported new processing types
- `/Users/luca/dev/realitycam/apps/mobile/hooks/index.ts` - Exported useCaptureProcessing hook
- `/Users/luca/dev/realitycam/apps/mobile/package.json` - Added pako and @types/pako dependencies
- `/Users/luca/dev/realitycam/docs/sprint-artifacts/sprint-status.yaml` - Updated story status to review

---

_Story created by BMAD Create Story Workflow_
_Date: 2025-11-23_
_Epic: 3 - Photo Capture with LiDAR Depth_
_Implementation completed: 2025-11-23_
