# Story Context: 4-3 Offline Storage and Auto-Upload

**Story Key:** 4-3-offline-storage-auto-upload
**Status:** ready-for-dev
**Generated:** 2025-11-23

---

## 1. Story Reference

**File:** `docs/sprint-artifacts/stories/story-4-3-offline-storage-auto-upload.md`

**Summary:** Implement secure local storage for offline captures with automatic upload when connectivity returns. Captures are encrypted using Secure Enclave-backed keys via expo-secure-store, stored persistently in the app's document directory, and automatically uploaded (oldest first) when network becomes available. Includes storage quota management, cleanup after successful uploads, and offline status UI indicators.

**Key Acceptance Criteria:**
- AC-1: Local file storage for offline captures using expo-file-system
- AC-2: Secure Enclave-backed encryption with AES-256-GCM
- AC-3: Capture data persistence across app restarts
- AC-4: Auto-upload triggering when network becomes available
- AC-5: Storage quota management (50 captures or 500MB limit)
- AC-6: Cleanup after successful upload
- AC-7: Offline status indicators in UI

---

## 2. Epic Context

**Epic:** 4 - Upload, Processing & Evidence Generation
**Tech Spec:** `docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-4.md`

This story implements AC-4.3 from Epic 4. It builds on:
- **Story 4-1:** Backend capture upload endpoint (POST /api/v1/captures) - COMPLETED
- **Story 4-2:** Upload queue with retry logic - COMPLETED

Subsequent stories:
- Story 4-4: Assertion verification (backend processes uploads)
- Story 4-5+: Backend evidence processing

---

## 3. Documentation Artifacts

### 3.1 Epic 4 Tech Spec
**Path:** `docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-4.md`

**Relevant Sections:**
- AC-4.3: Offline Storage and Auto-Upload (lines 743-749)
- Workflows: Offline Upload Queue State Machine (lines 553-584)
- Non-Functional: Offline Resilience requirements (lines 637-641)
- Mobile Dependencies (lines 699-707)

**Key Requirements from AC-4.3:**
```
1. Captures taken offline are stored in encrypted local storage using Secure Enclave-backed key
2. Offline captures display "Pending upload" badge with timestamp warning
3. When connectivity returns, captures automatically queue for upload
4. Upload order preserves capture chronology (oldest first)
5. Encryption uses expo-secure-store for key management
```

**Offline Resilience NFR (lines 637-641):**
```
- Captures stored in encrypted local storage when offline
- Queue persisted to device (survives app restart)
- Automatic retry when connectivity returns
- User notified of pending uploads with timestamp warning
```

### 3.2 Story 4-2 Context (Patterns to Follow)
**Path:** `docs/sprint-artifacts/story-contexts/context-4-2-upload-queue-retry.md`

**Key Patterns from Story 4-2:**
1. **Zustand Persistence:** Use `persist` middleware with AsyncStorage adapter
2. **Hydration Recovery:** Reset interrupted uploads to pending on hydration
3. **State Machine:** Follow established status flow: pending -> uploading -> processing -> completed
4. **Network Awareness:** Use `useNetworkStatus` hook with 300ms debounce
5. **Logging Pattern:** Use `[moduleName]` prefix for console logs
6. **Selector Pattern:** Export selectors for efficient component subscriptions

---

## 4. Existing Code Interfaces

### 4.1 Upload Queue Store (To Extend)
**Path:** `apps/mobile/store/uploadQueueStore.ts`

**Key Features Already Implemented:**
- Zustand store with AsyncStorage persistence
- Sequential queue processing (one at a time)
- Status tracking: pending, uploading, processing, completed, failed, permanently_failed
- Hydration recovery for interrupted uploads (lines 363-380)
- Selectors: `selectPendingItems`, `selectFailedItems`, `selectCompletedItems`, `selectQueueCounts`

**Current QueuedCapture Interface (from store):**
```typescript
interface QueuedCapture {
  capture: ProcessedCapture;
  status: QueuedCaptureStatus;
  retryCount: number;
  queuedAt: string;
  lastAttemptAt?: string;
  completedAt?: string;
  error?: UploadError;
  captureId?: string;
  verificationUrl?: string;
  progress?: number;
}
```

**Extensions Needed:**
- Add `storageLocation: 'memory' | 'disk'` field
- Add `isOfflineCapture: boolean` flag
- Add `restoreFromStorage()` action for app startup
- Modify `enqueue()` to optionally save to disk when offline

### 4.2 useUploadQueue Hook (To Extend)
**Path:** `apps/mobile/hooks/useUploadQueue.ts`

**Key Functions:**
- `processQueue()` - Processes next pending item when network available
- `processUpload(item)` - Handles single upload with progress tracking
- Network awareness via `useNetworkStatus` hook
- Auto-starts queue when `isInternetReachable` becomes true

**Extensions Needed:**
- Load disk-based captures when `storageLocation === 'disk'`
- Trigger cleanup after successful upload of offline captures
- Pause (not fail) uploads when network is lost mid-upload

### 4.3 useNetworkStatus Hook (Existing)
**Path:** `apps/mobile/hooks/useNetworkStatus.ts`

**Interface:**
```typescript
interface UseNetworkStatusReturn {
  isConnected: boolean | null;
  isInternetReachable: boolean | null;
  connectionType: ConnectionType;
  refresh: () => Promise<void>;
}
```

**Features:**
- 300ms debounce on network state changes
- Initial fetch on mount
- Automatic subscription to NetInfo changes
- Manual refresh function

### 4.4 Upload Service (Existing)
**Path:** `apps/mobile/services/uploadService.ts`

**Key Functions:**
- `uploadCapture(capture, onProgress)` - Multipart upload with progress
- `buildDeviceAuthHeaders(metadataJson)` - Device auth headers
- Error classification by HTTP status code

**Pattern for Loading from Disk:**
When `storageLocation === 'disk'`, need to:
1. Retrieve encryption key from expo-secure-store
2. Decrypt capture files
3. Load into ProcessedCapture format
4. Upload via existing `uploadCapture()` function

### 4.5 Retry Strategy Utils (Existing)
**Path:** `apps/mobile/utils/retryStrategy.ts`

**Functions:**
- `calculateBackoffDelay(retryCount, config)` - Exponential backoff
- `shouldRetry(error, retryCount, config)` - Check if error is retryable
- `isMaxRetriesExceeded(retryCount, config)` - Max attempts check
- `calculateDelayWithRetryAfter(error, retryCount, config)` - Respects 429 Retry-After

**Retryable Errors:** NETWORK_ERROR, SERVER_ERROR, RATE_LIMITED, TIMEOUT, UNKNOWN
**Non-Retryable:** VALIDATION_ERROR, AUTH_ERROR, NOT_FOUND, PAYLOAD_TOO_LARGE

---

## 5. Shared Types

### 5.1 Current Upload Types
**Path:** `packages/shared/src/types/upload.ts`

**Types to Extend:**
```typescript
// Add to QueuedCapture interface:
export interface QueuedCapture {
  // ... existing fields
  storageLocation?: 'memory' | 'disk';  // NEW: Where capture data is stored
  isOfflineCapture?: boolean;            // NEW: True if captured while offline
}

// NEW: Storage quota status type
export type StorageQuotaStatus = 'ok' | 'warning' | 'exceeded';

// NEW: Offline capture metadata with encryption info
export interface OfflineCaptureMetadata {
  captureId: string;
  keyId: string;           // Reference to key in expo-secure-store
  iv: string;              // Base64 IV for AES-GCM
  algorithm: 'aes-256-gcm';
  createdAt: string;
  photoSize: number;       // Bytes
  depthSize: number;       // Bytes
  metadataSize: number;    // Bytes
}
```

### 5.2 ProcessedCapture Type (Input)
**Path:** `packages/shared/src/types/capture.ts`

```typescript
export interface ProcessedCapture {
  id: string;
  photoUri: string;              // Local file URI to captured JPEG
  photoHash: string;             // SHA-256 base64 hash
  compressedDepthMap: string;    // Base64-encoded gzipped depth map
  depthDimensions: { width: number; height: number };
  metadata: CaptureMetadata;
  assertion?: string;            // Base64 device assertion
  status: CaptureStatus;
  createdAt: string;
}
```

---

## 6. Development Constraints

### 6.1 Architecture Constraints
- **Encryption Required:** All offline captures must be encrypted with Secure Enclave-backed key
- **Sequential Processing:** Upload queue processes one item at a time
- **Chronological Order:** Offline captures upload oldest first (FIFO)
- **Persistence Required:** Queue and offline captures survive app restart
- **Network Pause:** Network loss during upload should pause (not fail) the upload

### 6.2 Storage Constraints
- **Storage Location:** Use `documentDirectory` (persists across app updates)
- **Quota Limits:**
  - MAX_CAPTURES: 50 captures
  - MAX_STORAGE_BYTES: 500MB (500 * 1024 * 1024)
  - WARNING_THRESHOLD: 80% of quota
- **File Structure:**
  ```
  {documentDirectory}/
    captures/
      {captureId}/
        photo.jpg.enc          # Encrypted photo
        depth.gz.enc           # Encrypted depth map
        metadata.json.enc      # Encrypted metadata
        encryption.json        # IV and key reference (not encrypted)
  ```

### 6.3 Encryption Constraints
- **Algorithm:** AES-256-GCM (symmetric encryption)
- **Key Storage:** expo-secure-store with Secure Enclave backing
- **Key Naming:** `capture-encryption-key-{keyId}`
- **IV:** Unique per capture, stored with capture metadata
- **Key Derivation:** Consider using a master key per-device vs per-capture keys

### 6.4 Auto-Upload Constraints
- **Trigger:** `isInternetReachable === true` from useNetworkStatus
- **Debounce:** Network state already debounced 300ms in useNetworkStatus
- **Order:** Process in chronological order (oldest first)
- **Concurrency:** One upload at a time
- **Pause on Disconnect:** Network loss pauses current upload, does not fail it

---

## 7. Testing Context

### 7.1 Unit Test Targets
- `offlineStorage.ts`: Encryption/decryption round-trip
- `captureIndex.ts`: Index CRUD operations, integrity checking
- `storageQuota.ts`: Quota calculation, status thresholds
- `captureCleanup.ts`: File deletion, cleanup batch operations

### 7.2 Integration Test Requirements
- Offline capture -> storage -> restore -> upload flow
- App restart with pending offline captures -> queue restoration
- Storage quota enforcement (warning at 80%, block at 100%)
- Cleanup after successful upload

### 7.3 Manual Testing Scenarios
- Airplane mode capture -> disable airplane mode -> auto-upload
- App kill with pending captures -> relaunch -> uploads resume
- Fill storage to quota -> verify warning appears
- Cleanup after successful upload -> verify files deleted

### 7.4 Test Framework
- Jest for unit tests
- Mock expo-secure-store for encryption key tests
- Mock expo-file-system for file operations
- Mock AsyncStorage for persistence tests

---

## 8. File Structure After Implementation

```
apps/mobile/
+-- services/
|   +-- offlineStorage.ts          # NEW - Local file storage with encryption
|   +-- captureIndex.ts            # NEW - Index of stored captures
|   +-- storageQuota.ts            # NEW - Quota tracking and management
|   +-- captureCleanup.ts          # NEW - File cleanup after upload
+-- components/
|   +-- OfflineCaptureBadge.tsx    # NEW - Status badge component
|   +-- StorageUsageIndicator.tsx  # NEW - Storage usage display
+-- store/
|   +-- uploadQueueStore.ts        # MODIFIED - Add disk storage support
+-- hooks/
|   +-- useUploadQueue.ts          # MODIFIED - Auto-upload on network recovery
+-- __tests__/
|   +-- services/
|       +-- offlineStorage.test.ts # NEW - Encryption tests
|       +-- storageQuota.test.ts   # NEW - Quota tests

packages/shared/src/
+-- types/
|   +-- upload.ts                  # MODIFIED - Add offline storage types
+-- index.ts                       # MODIFIED - Export new types
```

---

## 9. Implementation Notes

### 9.1 Encryption Implementation

```typescript
// encryption.json structure
interface CaptureEncryption {
  keyId: string;           // Reference to key in expo-secure-store
  iv: string;              // Base64 IV for AES-GCM
  algorithm: 'aes-256-gcm';
  createdAt: string;
}

// Key storage in expo-secure-store
// Key name: `capture-encryption-key-{keyId}`
// Value: Base64-encoded 256-bit key
```

**Encryption Approach:**
1. Generate random 256-bit key for each capture (or use device master key)
2. Store key in expo-secure-store (Secure Enclave backed)
3. Generate random IV for AES-GCM
4. Encrypt photo, depth, metadata separately with same key/IV
5. Store encryption.json (unencrypted) with IV and key reference

**Dependencies for Encryption:**
```json
{
  "expo-crypto": "~14.0.0"  // For AES encryption, already present
}
```

### 9.2 Auto-Upload Flow

```
App Launch
    |
    v
[Restore Queue from Storage]
    |
    +-- For each stored capture:
    |       - Load from disk (encrypted)
    |       - Add to queue with status: pending
    |       - Set storageLocation: disk
    |
    v
[Subscribe to Network Status]
    |
    +-- On isInternetReachable === true:
    |       - Check for pending uploads
    |       - Start queue processing
    |
    v
[Upload Loop]
    |
    +-- Pick oldest pending capture
    |       - If storageLocation: disk, load from storage
    |       - Decrypt capture data
    |       - Upload via uploadService
    |       - On success: cleanup local files
    |       - On failure: apply retry logic
```

### 9.3 Quota Management

```typescript
const QUOTA_CONFIG = {
  MAX_CAPTURES: 50,
  MAX_STORAGE_BYTES: 500 * 1024 * 1024, // 500MB
  WARNING_THRESHOLD: 0.8, // 80%
  STALE_CAPTURE_DAYS: 7,  // Warn for captures older than 7 days
};

interface QuotaStatus {
  status: 'ok' | 'warning' | 'exceeded';
  captureCount: number;
  maxCaptures: number;
  storageUsedBytes: number;
  maxStorageBytes: number;
  oldestCaptureAge?: number; // hours
}
```

### 9.4 Cleanup Strategy

After successful upload:
1. Delete local photo.jpg.enc
2. Delete local depth.gz.enc
3. Delete local metadata.json.enc
4. Delete encryption.json
5. Remove capture directory
6. Keep queue record (for history/verification_url)
7. Optionally delete encryption key from secure store

Handle cleanup failures gracefully - log error, don't throw.

### 9.5 Error Handling

| Scenario | Handling |
|----------|----------|
| Encryption key missing | Re-generate key, existing captures unrecoverable (log error) |
| File read failure | Mark capture as corrupted, exclude from queue |
| Storage quota exceeded | Block new captures, prompt user to free space |
| Cleanup failure | Log error, capture remains (will retry next time) |
| Corrupted index | Rebuild from filesystem scan |
| Network loss mid-upload | Pause upload, resume when network returns |

---

## 10. Dependencies

### 10.1 Current Mobile Dependencies (Already Present)
**Path:** `apps/mobile/package.json`

```json
{
  "dependencies": {
    "@react-native-async-storage/async-storage": "2.2.0",
    "@react-native-community/netinfo": "^11.0.0",
    "expo-crypto": "~15.0.0",
    "expo-file-system": "~19.0.0",
    "expo-secure-store": "~15.0.0",
    "zustand": "^5.0.0"
  }
}
```

All required dependencies are already present.

---

## 11. Acceptance Criteria Checklist

- [ ] AC-1: Local file storage using expo-file-system in document directory
- [ ] AC-2: AES-256-GCM encryption with Secure Enclave-backed keys via expo-secure-store
- [ ] AC-3: Queue restoration on app restart, preserving FIFO order
- [ ] AC-4: Auto-upload triggered by isInternetReachable, network pause (not fail)
- [ ] AC-5: Quota management (50 captures / 500MB), warning at 80%
- [ ] AC-6: Cleanup local files after successful upload
- [ ] AC-7: OfflineCaptureBadge and StorageUsageIndicator components

---

## 12. Story-Specific Dev Notes from Story File

### 12.1 File Storage Structure
```
{documentDirectory}/
  captures/
    {captureId}/
      photo.jpg.enc          # Encrypted photo
      depth.gz.enc           # Encrypted depth map
      metadata.json.enc      # Encrypted metadata
      encryption.json        # IV and key reference (not encrypted)
```

### 12.2 Tasks Overview (from Story)
1. Create Offline Storage Service (AC: 1, 2)
2. Implement Storage Decryption and Retrieval (AC: 1, 2, 3)
3. Implement Storage Persistence Layer (AC: 3)
4. Extend Upload Queue Store for Offline Storage (AC: 3, 4)
5. Implement Auto-Upload Trigger (AC: 4)
6. Implement Storage Quota Management (AC: 5)
7. Implement Cleanup Service (AC: 6)
8. Add Offline Status UI Components (AC: 7)
9. Update Shared Types (AC: all)
10. Integration and Testing (AC: all)

---

_Context generated by Story Context Assembly Workflow_
_Date: 2025-11-23_
