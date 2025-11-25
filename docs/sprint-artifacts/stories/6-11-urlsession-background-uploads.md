# Story 6.11: URLSession Background Uploads

**Status:** Done
**Epic:** 6 - Native Swift Implementation
**Sprint:** Current

## Story Description
As a mobile user, I want my captures to upload in the background even when the app is closed so that I don't need to keep the app open to ensure my photos are uploaded.

## Acceptance Criteria

### AC1: Background Upload Session
- Uploads use URLSession background configuration
- Uploads continue after app termination
- App woken on completion to update status

### AC2: Multipart Form-Data Upload
- JPEG, depth, metadata, and assertion sent as multipart form-data
- Content-Type boundary properly formatted
- File parts use correct MIME types

### AC3: Device Authentication
- Requests signed with device Ed25519 signature
- X-Device-Id header includes device UUID
- X-Device-Timestamp header includes millisecond timestamp
- X-Device-Signature header includes base64 signature

### AC4: Upload Progress Tracking
- Progress tracked via delegate callbacks
- CaptureStore status updated (pending -> uploading -> uploaded/failed)
- Upload result (server ID, verification URL) stored

### AC5: Temp File Management
- Request body written to temp file for background uploads
- Temp files cleaned up after upload completion
- Temp directory doesn't exceed storage limits

## Technical Notes

### Files to Create/Modify
- `ios/Rial/Core/Networking/UploadService.swift` - Background upload service
- `ios/Rial/Core/Networking/APIClient.swift` - URLSession wrapper
- `ios/Rial/Core/Networking/DeviceSignature.swift` - Request signing
- `ios/Rial/App/AppDelegate.swift` - Background completion handler
- `ios/RialTests/Networking/UploadServiceTests.swift` - Unit tests

### Background Upload Configuration
```swift
let config = URLSessionConfiguration.background(withIdentifier: "app.rial.upload")
config.isDiscretionary = false
config.sessionSendsLaunchEvents = true
```

### Request Headers
```
Content-Type: multipart/form-data; boundary=...
X-Device-Id: <device-uuid>
X-Device-Timestamp: <epoch-millis>
X-Device-Signature: <base64-signature>
```

## Dependencies
- Story 6.1: Initialize Native iOS Project (completed)
- Story 6.9: CoreData Capture Queue (completed)
- Story 6.10: iOS Data Protection Encryption (completed)

## Definition of Done
- [x] UploadService uploads captures via background URLSession
- [x] Device authentication headers attached to requests
- [x] Multipart form-data properly formatted
- [x] Upload status tracked in CaptureStore
- [x] Unit tests verify upload functionality (11 tests passing)
- [x] Build succeeds

## Estimation
- Points: 5
- Complexity: Complex (background sessions, multipart, auth)
