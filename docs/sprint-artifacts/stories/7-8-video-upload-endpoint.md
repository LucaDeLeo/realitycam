# Story 7-8-video-upload-endpoint: Video Upload Endpoint

## Story Overview
- **Epic:** 7 - Video Capture with LiDAR Depth
- **Story ID:** 7-8-video-upload-endpoint
- **Priority:** P0
- **Estimated Effort:** L
- **Dependencies:** Story 7-7-video-local-processing-pipeline, Story 4-1-photo-upload-endpoint (patterns), Story 6-9-coredata-capture-persistence

## User Story

As a **mobile app**,
I want **to upload video captures with depth and attestation data**,
So that **the backend can verify and process them**.

## Story Context

This story implements the full video upload pipeline, spanning both iOS and Rust backend:

**iOS (VideoUploadService):**
- Extends UploadService patterns from Story 6-12 for video uploads
- Uses URLSession background uploads that survive app termination
- Multipart form-data encoding for large video files (~30-45MB)
- Integrates with ProcessedVideoCapture from Story 7-7
- CoreData persistence for video captures (deferred from Story 7-7)

**Backend (Rust/Axum):**
- New `POST /api/v1/captures/video` endpoint
- Multipart parsing for video, depth_data, hash_chain, and metadata parts
- S3 storage for video file and depth blob
- Creates capture record with type="video" and status="processing"
- Returns capture_id and verification_url

### Key Design Decisions

1. **Separate video endpoint:** Video uploads use `/api/v1/captures/video` rather than extending `/api/v1/captures` to keep photo and video processing paths distinct and maintainable.

2. **Background upload (iOS):** Uses URLSession background configuration so uploads continue even when app is terminated. This is critical for ~30-45MB uploads that may take minutes on slow connections.

3. **Rate limiting:** 5 videos/hour/device to prevent abuse while allowing legitimate use cases.

4. **Processing status:** Backend immediately returns "processing" status. Actual verification (hash chain, depth analysis) happens asynchronously in subsequent stories (7-9, 7-10).

5. **Chunked upload support:** For reliability on large files, support streaming/chunked uploads rather than loading entire file into memory.

---

## Acceptance Criteria

### AC-7.8.1: Video Upload Endpoint (Backend)
**Given** a processed video capture is ready for upload
**When** the app calls `POST /api/v1/captures/video` with multipart/form-data:
- Part `video`: MP4/MOV binary (~20MB)
- Part `depth_data`: gzipped depth keyframes (~10MB)
- Part `hash_chain`: JSON with frame hashes and checkpoints
- Part `metadata`: JSON with attestation

**Then** the backend:
1. Validates device signature headers
2. Verifies device exists and is registered
3. Stores video and depth data to S3
4. Creates pending capture record with type="video"
5. Returns capture ID and "processing" status

### AC-7.8.2: Video Upload Response Format
**Given** a successful video upload
**When** the backend returns a response
**Then** the response format is:
```json
{
  "data": {
    "capture_id": "uuid",
    "type": "video",
    "status": "processing",
    "verification_url": "https://realitycam.app/verify/{uuid}"
  }
}
```

### AC-7.8.3: Video Upload Size Limits
**Given** video file size constraints
**When** a video upload is received
**Then**:
- Video file: max 100MB (accounts for 15s 4K video worst case)
- Depth data: max 20MB (compressed)
- Hash chain: max 1MB (JSON with up to 450 hashes)
- Metadata: max 100KB

### AC-7.8.4: iOS Video Upload Service
**Given** a ProcessedVideoCapture from Story 7-7
**When** upload is initiated
**Then**:
- Multipart request created with all 4 parts
- Device auth headers included (X-Device-Id, X-Device-Signature, X-Device-Timestamp)
- Background URLSession task created
- Upload continues even if app is backgrounded/terminated
- Progress tracked via delegate

### AC-7.8.5: CoreData Video Persistence (iOS)
**Given** a ProcessedVideoCapture ready for upload
**When** saved to local storage
**Then**:
- Video capture entity created in CoreData
- Status set to "pending_upload"
- All file URLs stored correctly
- Supports offline queue integration
- Status updated to "uploading" when upload starts
- Status updated to "uploaded" or "failed" on completion

### AC-7.8.6: Rate Limiting
**Given** rate limiting configuration of 5 videos/hour/device
**When** a device exceeds the limit
**Then**:
- Backend returns 429 Too Many Requests
- Response includes retry-after header
- iOS queues upload for later retry

### AC-7.8.7: Upload Error Handling
**Given** various failure scenarios
**When** upload fails due to:
- Network error: Retry with exponential backoff
- 401 Unauthorized: Device re-registration required
- 413 Payload Too Large: Reject with clear error
- 429 Rate Limited: Queue for retry after delay
- 500 Server Error: Retry with backoff

**Then** appropriate error handling and recovery occurs

---

## Technical Requirements

### Backend: Video Upload Endpoint

```rust
// routes/captures_video.rs

/// POST /api/v1/captures/video - Upload a new video capture
///
/// Accepts multipart form data with:
/// - video: MP4/MOV binary (max 100MB)
/// - depth_data: Gzipped depth keyframes (max 20MB)
/// - hash_chain: JSON with frame hashes (max 1MB)
/// - metadata: JSON metadata with attestation (max 100KB)
///
/// Device authentication is handled by DeviceAuthLayer middleware.
///
/// # Responses
/// - 202 Accepted: Video uploaded successfully, processing queued
/// - 400 Bad Request: Validation error
/// - 401 Unauthorized: Device auth failed
/// - 413 Payload Too Large: File exceeds size limit
/// - 429 Too Many Requests: Rate limit exceeded
/// - 500 Internal Server Error: Storage or database error
async fn upload_video(
    State(state): State<AppState>,
    Extension(request_id): Extension<Uuid>,
    Extension(device_ctx): Extension<DeviceContext>,
    multipart: Multipart,
) -> Result<(StatusCode, Json<ApiResponse<VideoUploadResponse>>), ApiErrorWithRequestId>
```

### Backend: Video Metadata Payload

```rust
// types/video_capture.rs

#[derive(Debug, Deserialize)]
pub struct VideoUploadMetadata {
    pub started_at: DateTime<Utc>,
    pub ended_at: DateTime<Utc>,
    pub duration_ms: u64,
    pub frame_count: u32,
    pub depth_keyframe_count: u32,
    pub resolution: Resolution,
    pub codec: String,                   // "h264" or "hevc"
    pub device_model: String,
    pub location: Option<CaptureLocation>,
    pub attestation_level: String,
    pub hash_chain_final: String,        // Base64 final hash
    pub assertion: String,               // Base64 DCAppAttest
    pub checkpoints: Vec<HashCheckpoint>,
    pub is_partial: bool,
}

#[derive(Debug, Deserialize)]
pub struct HashCheckpoint {
    pub index: u32,
    pub frame_number: u32,
    pub hash: String,                    // Base64
    pub timestamp: f64,
}

#[derive(Debug, Serialize)]
pub struct VideoUploadResponse {
    pub capture_id: Uuid,
    pub r#type: String,                  // "video"
    pub status: String,                  // "processing"
    pub verification_url: String,
}
```

### Backend: Database Schema Extension

```sql
-- Video captures use same captures table with type discriminator
-- Add video-specific columns (migration)

ALTER TABLE captures ADD COLUMN capture_type VARCHAR(16) DEFAULT 'photo';
ALTER TABLE captures ADD COLUMN video_s3_key VARCHAR(255);
ALTER TABLE captures ADD COLUMN hash_chain_s3_key VARCHAR(255);
ALTER TABLE captures ADD COLUMN duration_ms BIGINT;
ALTER TABLE captures ADD COLUMN frame_count INT;
ALTER TABLE captures ADD COLUMN is_partial BOOLEAN DEFAULT FALSE;
ALTER TABLE captures ADD COLUMN checkpoint_index INT;
```

### iOS: VideoUploadService

```swift
// Core/Networking/VideoUploadService.swift

/// Service for uploading video captures with background URLSession support.
///
/// Extends photo upload patterns for larger video files (~30-45MB).
/// Uses background URLSession for uploads that survive app termination.
final class VideoUploadService: NSObject {
    private static let logger = Logger(subsystem: "app.rial", category: "video-upload")
    private static let sessionIdentifier = "app.rial.video-upload"

    private let baseURL: URL
    private let captureStore: CaptureStore
    private let keychain: KeychainService

    /// Upload a processed video capture
    func upload(_ capture: ProcessedVideoCapture) async throws

    /// Resume pending video uploads from previous session
    func resumePendingUploads() async
}
```

### iOS: CoreData Video Entity

```swift
// Core/Storage/VideoCaptureEntity.swift

/// CoreData entity for video capture persistence
/// Extends CaptureEntity pattern from Story 6-9

@objc(VideoCaptureEntity)
class VideoCaptureEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var videoURL: URL
    @NSManaged var depthDataURL: URL
    @NSManaged var hashChainData: Data
    @NSManaged var metadataData: Data
    @NSManaged var thumbnailData: Data
    @NSManaged var status: String
    @NSManaged var createdAt: Date
    @NSManaged var uploadedAt: Date?
    @NSManaged var serverCaptureId: UUID?
    @NSManaged var verificationUrl: String?
    @NSManaged var durationMs: Int64
    @NSManaged var frameCount: Int32
    @NSManaged var isPartial: Bool
}
```

### Integration Points

1. **Story 7-7 (VideoProcessingPipeline):** Input is `ProcessedVideoCapture` from processing pipeline

2. **Story 4-1 (Photo Upload):** Backend patterns for multipart parsing, S3 storage, device auth

3. **Story 6-9 (CaptureStore):** CoreData patterns for video persistence

4. **Story 6-12 (UploadService):** Background URLSession patterns for iOS

5. **Story 7-9 (Depth Analysis):** Backend consumes uploaded depth_data

6. **Story 7-10 (Hash Chain Verification):** Backend consumes uploaded hash_chain

---

## Implementation Tasks

### Backend Tasks

#### Task 1: Create Video Capture Types
**File:** `backend/src/types/video_capture.rs`

Define video capture types:
- [ ] Create `VideoUploadMetadata` struct with all fields
- [ ] Create `HashCheckpoint` struct
- [ ] Create `VideoUploadResponse` struct
- [ ] Add validation methods for metadata fields
- [ ] Add serde Serialize/Deserialize derives

#### Task 2: Create Database Migration
**File:** `backend/migrations/YYYYMMDDHHMMSS_add_video_captures.sql`

Add video-specific columns:
- [ ] Add `capture_type` column with default 'photo'
- [ ] Add `video_s3_key` column
- [ ] Add `hash_chain_s3_key` column
- [ ] Add `duration_ms` column
- [ ] Add `frame_count` column
- [ ] Add `is_partial` column
- [ ] Add `checkpoint_index` column
- [ ] Create index on capture_type for filtering

#### Task 3: Create Video Upload Route
**File:** `backend/src/routes/captures_video.rs`

Implement video upload endpoint:
- [ ] Create `router()` function returning Router<AppState>
- [ ] Implement `upload_video` handler
- [ ] Implement `parse_video_multipart` for 4-part parsing
- [ ] Add size validation for each part
- [ ] Integrate with DeviceAuthLayer middleware
- [ ] Add tracing for observability

#### Task 4: Extend Storage Service for Video
**File:** `backend/src/services/storage.rs`

Add video upload methods:
- [ ] Implement `upload_video_files()` method
- [ ] Handle video file upload to S3 with content-type
- [ ] Handle depth_data upload to S3
- [ ] Handle hash_chain upload to S3
- [ ] Return S3 keys for all files

#### Task 5: Update AppState and Router
**File:** `backend/src/routes/mod.rs`

Register video routes:
- [ ] Import captures_video module
- [ ] Add `/captures/video` route to router
- [ ] Configure rate limiting (5/hour/device)

#### Task 6: Update Capture Model for Video
**File:** `backend/src/models/capture.rs`

Extend capture model:
- [ ] Add video-specific fields to Capture struct
- [ ] Add `CaptureType` enum (photo, video)
- [ ] Update query_as! macros for new columns

### iOS Tasks

#### Task 7: Create VideoUploadService
**File:** `ios/Rial/Core/Networking/VideoUploadService.swift`

Implement video upload service:
- [ ] Create VideoUploadService class extending NSObject
- [ ] Configure background URLSession
- [ ] Implement `upload(_:)` method
- [ ] Create multipart request with 4 parts
- [ ] Add device auth headers
- [ ] Implement URLSessionDelegate methods

#### Task 8: Create VideoCaptureEntity
**File:** `ios/Rial/Core/Storage/VideoCaptureEntity.swift`

Create CoreData entity:
- [ ] Define VideoCaptureEntity as NSManagedObject subclass
- [ ] Add all required properties
- [ ] Add convenience initializer from ProcessedVideoCapture
- [ ] Add status enum for upload states

#### Task 9: Update CoreData Model
**File:** `ios/Rial/Rial.xcdatamodeld`

Add video entity to data model:
- [ ] Create VideoCapture entity in data model
- [ ] Define all attributes with correct types
- [ ] Set up relationships if needed
- [ ] Generate NSManagedObject subclass

#### Task 10: Extend CaptureStore for Video
**File:** `ios/Rial/Core/Storage/CaptureStore.swift`

Add video persistence methods:
- [ ] Implement `saveVideoCapture(_:)` method
- [ ] Implement `loadVideoCapture(id:)` method
- [ ] Implement `updateVideoCaptureStatus(_:for:)` method
- [ ] Implement `updateVideoUploadResult(for:serverCaptureId:verificationUrl:)` method
- [ ] Implement `pendingVideoUploads()` method

#### Task 11: Integrate VideoUploadService with UploadService
**File:** `ios/Rial/Core/Networking/UploadService.swift`

Update existing upload service:
- [ ] Add reference to VideoUploadService
- [ ] Add `uploadVideo(_:)` method that delegates to VideoUploadService
- [ ] Coordinate background session completion handlers

#### Task 12: Update AppDelegate for Background Uploads
**File:** `ios/Rial/App/AppDelegate.swift`

Handle video upload background events:
- [ ] Register VideoUploadService background session
- [ ] Implement `handleEventsForBackgroundURLSession` for video
- [ ] Resume pending uploads on app launch

---

## Test Requirements

### Backend Unit Tests
**File:** `backend/src/routes/captures_video_tests.rs`

- [ ] Test multipart parsing with valid data
- [ ] Test multipart parsing with missing parts
- [ ] Test size validation rejects oversized video
- [ ] Test size validation rejects oversized depth_data
- [ ] Test metadata validation with valid JSON
- [ ] Test metadata validation with invalid JSON
- [ ] Test VideoUploadResponse serialization

### Backend Integration Tests
**File:** `backend/tests/video_upload_integration.rs`

- [ ] Test full video upload flow with test fixtures
- [ ] Test S3 upload creates correct keys
- [ ] Test database record created with correct fields
- [ ] Test device auth validation on video endpoint
- [ ] Test rate limiting rejects after 5 uploads
- [ ] Test partial video metadata handling

### iOS Unit Tests
**File:** `ios/RialTests/Networking/VideoUploadServiceTests.swift`

- [ ] Test multipart request creation
- [ ] Test device auth headers included
- [ ] Test background session configuration
- [ ] Test task to capture mapping
- [ ] Test response parsing for upload result

### iOS Integration Tests
**File:** `ios/RialTests/Storage/VideoCaptureStoreTests.swift`

- [ ] Test saveVideoCapture persists correctly
- [ ] Test loadVideoCapture retrieves correctly
- [ ] Test updateVideoCaptureStatus updates correctly
- [ ] Test pendingVideoUploads returns correct captures

### E2E Tests (Manual/Device)
- [ ] Record 15s video and upload successfully
- [ ] Verify upload completes in background when app terminated
- [ ] Verify failed upload queued for retry
- [ ] Verify rate limiting triggers after 5 uploads
- [ ] Verify partial video upload with is_partial=true

---

## Definition of Done

- [ ] All acceptance criteria met (AC-7.8.1 through AC-7.8.7)
- [ ] Backend endpoint deployed and accessible
- [ ] iOS VideoUploadService implemented and integrated
- [ ] CoreData video entity created and working
- [ ] Unit tests passing with >= 80% coverage
- [ ] Integration tests passing on device
- [ ] Rate limiting verified (5/hour/device)
- [ ] Background upload verified on device
- [ ] No new lint errors (Clippy, SwiftLint)
- [ ] Documentation updated (code comments, DocC)
- [ ] Ready for Story 7-9 (Depth Analysis) integration

---

## Technical Notes

### Why Separate Video Endpoint?

Videos require different handling than photos:
1. **Larger files:** ~30-45MB vs ~2-5MB for photos
2. **More parts:** 4 multipart parts vs 3 for photos
3. **Async processing:** Video verification is more complex
4. **Different rate limits:** Fewer videos allowed per hour
5. **Different S3 structure:** Video files stored separately

### Background Upload Architecture (iOS)

```
+----------------+     +------------------+     +----------------+
| ProcessedVideo |---->| VideoUploadService|---->| URLSession     |
| Capture        |     | (foreground)      |     | (background)   |
+----------------+     +------------------+     +----------------+
                              |                        |
                              v                        v
                       +-------------+          +-------------+
                       | CaptureStore|<---------| Delegate    |
                       | (CoreData)  |          | (completion)|
                       +-------------+          +-------------+
```

URLSession background configuration ensures:
- Uploads continue when app is backgrounded
- Uploads continue when app is terminated
- App woken on completion for status update
- Automatic retry on network failures

### Size Budget

For 15-second 1080p video at 30fps:
- Video file: ~20-30MB (H.264 compressed)
- Depth data: ~10MB (150 keyframes, gzipped)
- Hash chain: ~100KB (450 hashes + checkpoints)
- Metadata: ~5KB

Conservative limits:
- Video: 100MB (allows 4K)
- Depth: 20MB
- Hash chain: 1MB
- Metadata: 100KB

---

## Source Document References

- **Epic:** docs/epics.md - Story 7.8: Video Upload Endpoint
- **Tech Spec:** docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-7.md
  - Section: APIs and Interfaces > Video Upload Endpoint
  - Section: Data Models > VideoUploadMetadata
  - Section: AC-7.7 (Video Upload)
- **Architecture:** docs/architecture.md - Upload patterns, S3 storage
- **Previous Stories:**
  - docs/sprint-artifacts/stories/7-7-video-local-processing-pipeline.md (ProcessedVideoCapture input)
  - docs/sprint-artifacts/stories/4-1-photo-upload-endpoint.md (Backend patterns, if available)
  - docs/sprint-artifacts/stories/6-12-upload-service.md (iOS upload patterns, if available)
  - docs/sprint-artifacts/stories/6-9-coredata-capture-persistence.md (CoreData patterns)

---

## Learnings from Previous Stories

Based on review of Story 7-7 and existing UploadService:

1. **Background URLSession (Story 6-12):** Use `URLSessionConfiguration.background` with `sessionSendsLaunchEvents = true` for uploads that survive app termination.

2. **Multipart Encoding (UploadService.swift):** Follow existing pattern with boundary, Content-Disposition headers, and proper CRLF line endings.

3. **CoreData Patterns (Story 6-9):** Use NSManagedObject subclass with @NSManaged properties. Save context on background queue.

4. **Device Auth (captures.rs):** Validate X-Device-Id, X-Device-Signature, X-Device-Timestamp headers via DeviceAuthLayer middleware.

5. **S3 Upload (storage.rs):** Use storage service methods for S3 operations. Return S3 keys for database storage.

6. **Error Handling (Story 7-7):** Processing should fail gracefully. If upload fails, queue for retry rather than losing capture.

7. **Progress Reporting (Story 7-7):** Use URLSessionTaskDelegate for upload progress. Update CaptureStore status on progress milestones.

8. **Rate Limiting (captures.rs):** Use tower_governor middleware layer. Configure per-device limits.

---

## FR Coverage

This story implements:
- **FR51:** App uploads video captures for backend verification

This story enables:
- **FR52:** Backend receives video for hash chain verification (Story 7-10)
- **FR53:** Backend receives depth data for temporal analysis (Story 7-9)
- **FR54:** Backend can generate C2PA video manifest (Story 7-12)
- **FR55:** Video available for verification page (Story 7-13)

---

_Story created: 2025-11-27_
_FR Coverage: FR51 (Video upload), enabling FR52, FR53, FR54, FR55_

---

## Dev Agent Record

### Status
**Status:** draft

### Context Reference
N/A (not yet created)

### File List
**To Be Created:**
- `backend/src/routes/captures_video.rs` - Video upload endpoint
- `backend/src/types/video_capture.rs` - Video capture types
- `backend/migrations/YYYYMMDDHHMMSS_add_video_captures.sql` - Schema extension
- `ios/Rial/Core/Networking/VideoUploadService.swift` - Video upload service
- `ios/Rial/Core/Storage/VideoCaptureEntity.swift` - CoreData entity
- `ios/RialTests/Networking/VideoUploadServiceTests.swift` - Unit tests
- `ios/RialTests/Storage/VideoCaptureStoreTests.swift` - Integration tests
- `backend/tests/video_upload_integration.rs` - Backend integration tests

**To Be Modified:**
- `backend/src/routes/mod.rs` - Register video routes
- `backend/src/services/storage.rs` - Add video upload methods
- `backend/src/models/capture.rs` - Extend for video fields
- `ios/Rial/Core/Storage/CaptureStore.swift` - Add video methods
- `ios/Rial/App/AppDelegate.swift` - Background session handling
- `ios/Rial/Rial.xcdatamodeld` - Add VideoCapture entity

### Completion Notes
N/A (story not yet implemented)
