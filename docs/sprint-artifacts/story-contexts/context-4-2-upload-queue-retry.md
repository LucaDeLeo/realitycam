# Story Context: 4-2 Upload Queue with Retry Logic

**Story Key:** 4-2-upload-queue-retry
**Status:** ready-for-dev
**Generated:** 2025-11-23

---

## 1. Story Reference

**File:** `docs/sprint-artifacts/stories/story-4-2-upload-queue-retry.md`

**Summary:** Implement a persistent upload queue with exponential backoff retry logic on the mobile client. When a capture enters the "ready" state, it is automatically added to a queue that processes items sequentially, retries failures with exponential backoff (up to 10 attempts), persists state across app restarts via AsyncStorage, and automatically triggers uploads when network connectivity is available.

**Key Acceptance Criteria:**
- AC-1: Upload queue service with sequential processing and Zustand store
- AC-2: Exponential backoff retry (1s, 2s, 4s, 8s, 5min cap, max 10 attempts)
- AC-3: Queue persistence via AsyncStorage with atomic writes
- AC-4: Network-aware upload triggering via @react-native-community/netinfo
- AC-5: Upload status tracking (pending/uploading/processing/completed/failed/permanently_failed)
- AC-6: Manual retry and cancel actions
- AC-7: Upload API integration with multipart form and device auth headers

---

## 2. Epic Context

**Epic:** 4 - Upload, Processing & Evidence Generation
**Tech Spec:** `docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-4.md`

This story implements AC-4.2 from Epic 4. It builds on:
- **Story 4-1:** Backend capture upload endpoint (POST /api/v1/captures) - COMPLETED
- **Story 3-5:** Local processing pipeline (ProcessedCapture type) - COMPLETED

Subsequent stories depend on this:
- Story 4-3: Offline storage and auto-upload (builds on queue infrastructure)
- Story 4-4: Assertion verification (backend processes uploads from this queue)

---

## 3. Documentation Artifacts

### 3.1 Epic 4 Tech Spec
**Path:** `docs/sprint-artifacts/epic-tech-specs/tech-spec-epic-4.md`

**Relevant Sections:**
- AC-4.2: Upload Queue with Retry (lines 737-741)
- Workflows: Offline Upload Queue State Machine (lines 553-584)
- Data Models: Mobile Types - QueuedCapture (lines 295-307)
- APIs: POST /api/v1/captures format (lines 311-383)
- Non-Functional: Performance targets (lines 589-605)
- Non-Functional: Security requirements (lines 609-634)
- Mobile Dependencies (lines 699-707)

**Upload Queue State Machine:**
```
                    [Network Available]
    +--------+          +----------+           +-----------+
    | pending|--------->| uploading|---------->| processing|
    +--------+          +----------+           +-----------+
        ^                    |                       |
        |                    | [Upload Error]        | [Server Complete]
        |                    v                       v
        |               +--------+             +---------+
        +---------------| failed |             | complete|
        [Retry Timer]   +--------+             +---------+
                             |
                             | [Max Retries]
                             v
                        +-----------+
                        |permanently|
                        |  failed   |
                        +-----------+
```

**Retry Schedule (Tech Spec):**
- Attempt 1: immediate
- Attempt 2: 1 second delay
- Attempt 3: 2 seconds delay
- Attempt 4: 4 seconds delay
- Attempt 5: 8 seconds delay
- Attempts 6-10: 5 minutes delay (max backoff cap)
- After 10 attempts: mark permanently failed

### 3.2 Story 4-1 Context (Backend Contract)
**Path:** `docs/sprint-artifacts/story-contexts/context-4-1-capture-upload-endpoint.md`

**Key Learnings from Story 4-1:**
- Response format: `{ data: { capture_id, status, verification_url }, meta: { request_id, timestamp } }`
- Device auth headers required: X-Device-Id, X-Device-Timestamp, X-Device-Signature
- Error codes: VALIDATION_ERROR (400), SIGNATURE_INVALID (401), DEVICE_NOT_FOUND (404), PAYLOAD_TOO_LARGE (413), RATE_LIMITED (429), STORAGE_ERROR (500)
- Multipart format: photo (image/jpeg), depth_map (application/gzip), metadata (application/json)

**Request Format (from context-4-1):**
```http
POST /api/v1/captures
Content-Type: multipart/form-data
X-Device-Id: {device_uuid}
X-Device-Timestamp: {unix_ms}
X-Device-Signature: {base64_signature}

--boundary
Content-Disposition: form-data; name="photo"; filename="capture.jpg"
Content-Type: image/jpeg
{JPEG binary ~3MB}
--boundary
Content-Disposition: form-data; name="depth_map"; filename="depth.gz"
Content-Type: application/gzip
{gzipped Float32Array ~1MB}
--boundary
Content-Disposition: form-data; name="metadata"
Content-Type: application/json
{"captured_at": "...", "device_model": "...", "photo_hash": "...", ...}
--boundary--
```

**Response Format (Success - 202):**
```json
{
  "data": {
    "capture_id": "550e8400-e29b-41d4-a716-446655440000",
    "status": "processing",
    "verification_url": "https://realitycam.app/verify/550e8400..."
  },
  "meta": {
    "request_id": "req-abc123",
    "timestamp": "2025-11-23T10:30:01Z"
  }
}
```

---

## 4. Existing Code Interfaces

### 4.1 ProcessedCapture Type (Input to Queue)
**Path:** `packages/shared/src/types/capture.ts`

```typescript
export interface ProcessedCapture {
  id: string;                    // UUID for this capture
  photoUri: string;              // Local file URI to captured JPEG
  photoHash: string;             // SHA-256 base64 hash of photo bytes
  compressedDepthMap: string;    // Base64-encoded gzipped depth map
  depthDimensions: {
    width: number;
    height: number;
  };
  metadata: CaptureMetadata;     // Assembled metadata for backend
  assertion?: string;            // Base64 device assertion (if available)
  status: CaptureStatus;         // 'ready' when entering queue
  createdAt: string;             // ISO timestamp when capture was created
}

export interface CaptureMetadata {
  captured_at: string;           // ISO timestamp of capture
  device_model: string;          // e.g., "iPhone 15 Pro"
  photo_hash: string;            // SHA-256 base64 hash
  depth_map_dimensions: {
    width: number;
    height: number;
  };
  location?: CaptureLocation;    // Optional GPS location
  assertion?: string;            // Base64 per-capture assertion
}

export type CaptureStatus =
  | 'capturing' | 'processing' | 'ready'
  | 'uploading' | 'completed' | 'failed';
```

### 4.2 useCaptureProcessing Hook (Produces ProcessedCapture)
**Path:** `apps/mobile/hooks/useCaptureProcessing.ts`

**Key Functions:**
- `processCapture(raw: RawCapture): Promise<ProcessedCapture>` - Processes raw capture into upload-ready package
- Compresses depth map with pako gzip
- Computes SHA-256 hash of photo
- Assembles CaptureMetadata

**Output:** ProcessedCapture with status='ready' - this is the queue input

### 4.3 Device Store (Zustand Pattern Reference)
**Path:** `apps/mobile/store/deviceStore.ts`

**Key Patterns to Follow:**
- Zustand with persist middleware using AsyncStorage
- `createJSONStorage(() => AsyncStorage)` for storage adapter
- `partialize` to select which state to persist
- `onRehydrateStorage` callback for hydration completion
- Selector pattern: `useDeviceStore((state) => state.keyId)`

**Relevant State for Upload Auth:**
```typescript
interface DeviceState {
  keyId: string | null;           // Secure Enclave key ID for signing
  isAttested: boolean;            // Whether device attestation completed
  capabilities: DeviceCapabilities | null;  // Device model, etc.
}
```

### 4.4 API Service (Pattern Reference)
**Path:** `apps/mobile/services/api.ts`

**Key Patterns:**
- `ApiError` class with code, message, statusCode
- `API_ERROR_CODES` constant object for typed error codes
- `base64ToUint8Array()` utility for encoding
- `uint8ArrayToBase64()` utility (private, available pattern)
- Timeout handling with AbortController
- Error classification by status code

**Error Codes to Extend:**
```typescript
export const API_ERROR_CODES = {
  TIMEOUT: 'TIMEOUT',
  NETWORK_ERROR: 'NETWORK_ERROR',
  RATE_LIMITED: 'RATE_LIMITED',
  NOT_IMPLEMENTED: 'NOT_IMPLEMENTED',
  SERVER_ERROR: 'SERVER_ERROR',
  UNKNOWN: 'UNKNOWN',
} as const;
```

**Need to Add:**
- `VALIDATION_ERROR` (400)
- `AUTH_ERROR` (401)
- `NOT_FOUND` (404)
- `PAYLOAD_TOO_LARGE` (413)

### 4.5 useCaptureAttestation Hook (Assertion Generation)
**Path:** `apps/mobile/hooks/useCaptureAttestation.ts`

**Key Interface:**
```typescript
interface UseCaptureAttestationReturn {
  generateAssertion: (metadata: AssertionMetadata) => Promise<CaptureAssertion | null>;
  isReady: boolean;        // Device attested and can generate assertions
  isGenerating: boolean;
}
```

**Note:** Per-capture assertions are already generated during capture (Story 3-4). The `ProcessedCapture.assertion` field contains the assertion string to include in upload.

---

## 5. Dependencies

### 5.1 Current Mobile Dependencies
**Path:** `apps/mobile/package.json`

```json
{
  "dependencies": {
    "@expo/app-integrity": "~0.1.0",
    "@react-native-async-storage/async-storage": "2.2.0",  // ALREADY PRESENT
    "@realitycam/shared": "workspace:*",
    "expo-crypto": "~15.0.0",
    "expo-file-system": "~19.0.0",
    "expo-secure-store": "~15.0.0",
    "pako": "^2.1.0",
    "zustand": "^5.0.0"   // ALREADY PRESENT
  }
}
```

### 5.2 Dependencies to Add
```json
{
  "dependencies": {
    "@react-native-community/netinfo": "^11.0.0"   // NEW - Network connectivity
  }
}
```

**Note:** `@react-native-async-storage/async-storage` is already present (v2.2.0).

---

## 6. Development Constraints

### 6.1 Architecture Constraints
- **Queue Processing:** Sequential, one upload at a time to avoid overwhelming server/network
- **State Atomicity:** Queue operations must be atomic (no partial state)
- **Network Awareness:** Upload only when connected, pause on disconnect (not fail)
- **Persistence:** Queue state survives app restart via AsyncStorage

### 6.2 Retry Logic Constraints
- **Retryable Errors:** Network errors, 5xx server errors, 429 with Retry-After
- **Non-Retryable Errors:** 400 (validation), 401 (auth), 404 (not found), 413 (too large)
- **Max Attempts:** 10 total attempts before permanent failure
- **Backoff Formula:**
  - Attempts 1-5: `delay = 2^(attempt-2) * 1000` (0, 1s, 2s, 4s, 8s)
  - Attempts 6-10: 5 minutes (300,000ms cap)

### 6.3 Device Auth Headers
Per Story 4-1, all uploads require device authentication:
- `X-Device-Id`: Device UUID from registration
- `X-Device-Timestamp`: Current Unix timestamp in milliseconds
- `X-Device-Signature`: Base64-encoded signature of `timestamp|body_hash`

**Signature Implementation Note:** The device key (`keyId`) is stored in deviceStore. Signing uses `@expo/app-integrity` assertion mechanism or stored credentials.

### 6.4 Network Debouncing
- Debounce network state changes by 300ms to prevent flapping
- Only trigger uploads after stable connectivity (not on brief reconnections)

---

## 7. Testing Context

### 7.1 Unit Test Targets
- `retryStrategy.ts`: Test backoff delay calculations for all attempt counts
- `retryStrategy.ts`: Test shouldRetry logic for all error types
- `uploadQueueStore.ts`: Test queue state transitions (enqueue, dequeue, markCompleted, markFailed)
- `uploadQueueStore.ts`: Test retry and cancel actions
- `uploadQueueStore.ts`: Test progress updates

### 7.2 Integration Test Requirements
- Queue persistence: Add items, kill app, restore, verify queue intact
- Network state: Mock netinfo, test upload triggering/pausing
- Retry flow: Mock failed uploads, verify backoff timing and state transitions

### 7.3 Test Data
- Mock `ProcessedCapture` objects with all required fields
- Mock network state changes (connected/disconnected)
- Mock upload responses (success, various errors)

### 7.4 Testing Framework
- Jest for unit tests (already configured in workspace)
- Mock AsyncStorage using `@react-native-async-storage/async-storage/jest/async-storage-mock`
- Mock netinfo using `@react-native-community/netinfo/jest/netinfo-mock`

---

## 8. File Structure After Implementation

```
apps/mobile/
+-- hooks/
|   +-- useNetworkStatus.ts        # NEW - Network monitoring with debounce
|   +-- useUploadQueue.ts          # NEW - Queue processing hook
|   +-- index.ts                   # MODIFIED - export new hooks
+-- services/
|   +-- api.ts                     # MODIFIED - add device auth headers, upload fn
|   +-- uploadService.ts           # NEW - Multipart upload to backend
+-- store/
|   +-- uploadQueueStore.ts        # NEW - Queue state management (Zustand)
+-- utils/
|   +-- retryStrategy.ts           # NEW - Exponential backoff calculations
+-- package.json                   # MODIFIED - add netinfo dependency

packages/shared/src/
+-- types/
|   +-- upload.ts                  # NEW - QueuedCapture, UploadError types
|   +-- index.ts                   # MODIFIED - export upload types
+-- index.ts                       # MODIFIED - re-export upload types
```

---

## 9. Type Definitions to Create

### 9.1 Upload Queue Types (`packages/shared/src/types/upload.ts`)

```typescript
/** Upload queue item status */
export type QueuedCaptureStatus =
  | 'pending'           // Waiting in queue
  | 'uploading'         // Currently uploading
  | 'processing'        // Server processing after upload
  | 'completed'         // Upload successful
  | 'failed'            // Failed, can retry
  | 'permanently_failed'; // Failed after max retries

/** Error classification for retry logic */
export type UploadErrorCode =
  | 'NETWORK_ERROR'     // No connectivity
  | 'SERVER_ERROR'      // 5xx response
  | 'VALIDATION_ERROR'  // 400 - don't retry
  | 'AUTH_ERROR'        // 401 - don't retry
  | 'NOT_FOUND'         // 404 - don't retry
  | 'PAYLOAD_TOO_LARGE' // 413 - don't retry
  | 'RATE_LIMITED'      // 429 - retry with Retry-After
  | 'UNKNOWN';          // Unknown error

/** Structured upload error */
export interface UploadError {
  code: UploadErrorCode;
  message: string;
  statusCode?: number;
  retryAfter?: number;  // Seconds to wait (from 429 Retry-After header)
}

/** Queue item wrapping a processed capture */
export interface QueuedCapture {
  /** Original processed capture */
  capture: ProcessedCapture;
  /** Current queue status */
  status: QueuedCaptureStatus;
  /** Number of upload attempts */
  retryCount: number;
  /** Timestamp when added to queue */
  queuedAt: string;
  /** Timestamp of last upload attempt */
  lastAttemptAt?: string;
  /** Timestamp when completed */
  completedAt?: string;
  /** Error from last failed attempt */
  error?: UploadError;
  /** Server-assigned capture ID after successful upload */
  captureId?: string;
  /** Verification URL from server */
  verificationUrl?: string;
  /** Upload progress 0-100 (during uploading status) */
  progress?: number;
}

/** Upload queue store state */
export interface UploadQueueState {
  /** Queued items */
  items: QueuedCapture[];
  /** Whether queue processor is running */
  isProcessing: boolean;
  /** ID of currently uploading item (if any) */
  currentUploadId: string | null;
}

/** Upload success response from backend */
export interface CaptureUploadResponse {
  capture_id: string;
  status: 'processing' | 'complete';
  verification_url: string;
}
```

---

## 10. Implementation Notes

### 10.1 Multipart Upload Implementation

Use `FormData` for multipart construction:

```typescript
async function uploadCapture(capture: ProcessedCapture): Promise<CaptureUploadResponse> {
  const formData = new FormData();

  // Photo part - read file as blob
  const photoResponse = await fetch(capture.photoUri);
  const photoBlob = await photoResponse.blob();
  formData.append('photo', photoBlob, 'capture.jpg');

  // Depth map part - convert base64 to blob
  const depthBytes = base64ToBytes(capture.compressedDepthMap);
  const depthBlob = new Blob([depthBytes], { type: 'application/gzip' });
  formData.append('depth_map', depthBlob, 'depth.gz');

  // Metadata part
  formData.append('metadata', JSON.stringify(capture.metadata));

  // Send with device auth headers
  const response = await fetch(`${API_BASE_URL}/api/v1/captures`, {
    method: 'POST',
    headers: buildDeviceAuthHeaders(),
    body: formData,
  });

  // Handle response...
}
```

### 10.2 Device Auth Headers Implementation

```typescript
import * as Crypto from 'expo-crypto';

async function buildDeviceAuthHeaders(body: string): Promise<Record<string, string>> {
  const deviceStore = useDeviceStore.getState();
  const deviceId = deviceStore.capabilities?.deviceId; // Need to verify this exists
  const timestamp = Date.now().toString();

  // Compute body hash
  const bodyHash = await Crypto.digestStringAsync(
    Crypto.CryptoDigestAlgorithm.SHA256,
    body,
    { encoding: Crypto.CryptoEncoding.BASE64 }
  );

  // Sign: timestamp|bodyHash
  // NOTE: Need to determine how to sign - may need keyId from deviceStore
  const signature = await signWithDeviceKey(`${timestamp}|${bodyHash}`);

  return {
    'X-Device-Id': deviceId,
    'X-Device-Timestamp': timestamp,
    'X-Device-Signature': signature,
  };
}
```

**Implementation Note:** The exact signing mechanism needs to be determined. Options:
1. Use `@expo/app-integrity` generateAssertionAsync with the signing payload
2. Use stored device key from Secure Store (if available from registration)
3. Consult Story 2-4 backend device registration for expected signature format

### 10.3 Network Status Hook Pattern

```typescript
import NetInfo, { NetInfoState } from '@react-native-community/netinfo';

export function useNetworkStatus() {
  const [isConnected, setIsConnected] = useState<boolean | null>(null);

  useEffect(() => {
    let debounceTimer: NodeJS.Timeout;

    const unsubscribe = NetInfo.addEventListener((state: NetInfoState) => {
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        setIsConnected(state.isConnected && state.isInternetReachable);
      }, 300); // 300ms debounce
    });

    // Initial check
    NetInfo.fetch().then((state) => {
      setIsConnected(state.isConnected && state.isInternetReachable);
    });

    return () => {
      unsubscribe();
      clearTimeout(debounceTimer);
    };
  }, []);

  return { isConnected };
}
```

### 10.4 Zustand Store with Persistence

```typescript
import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import AsyncStorage from '@react-native-async-storage/async-storage';

export const useUploadQueueStore = create<UploadQueueStoreState>()(
  persist(
    (set, get) => ({
      items: [],
      isProcessing: false,
      currentUploadId: null,

      enqueue: (capture: ProcessedCapture) => set((state) => ({
        items: [...state.items, {
          capture,
          status: 'pending',
          retryCount: 0,
          queuedAt: new Date().toISOString(),
        }],
      })),

      // ... other actions
    }),
    {
      name: 'realitycam-upload-queue',
      storage: createJSONStorage(() => AsyncStorage),
      partialize: (state) => ({
        items: state.items,
        // Don't persist isProcessing or currentUploadId
      }),
    }
  )
);
```

---

## 11. Error Handling Strategy

| Error Type | HTTP Code | Retry? | Action |
|------------|-----------|--------|--------|
| Network error | N/A | Yes | Wait for connectivity, then retry |
| Server error | 5xx | Yes | Exponential backoff |
| Rate limited | 429 | Yes | Use Retry-After header if present |
| Validation error | 400 | No | Mark failed, show user error |
| Auth error | 401 | No | Mark failed, may need re-registration |
| Not found | 404 | No | Mark failed, device not registered |
| Payload too large | 413 | No | Mark permanently failed |

---

## 12. Acceptance Criteria Checklist

- [ ] AC-1: Upload queue service with Zustand store, sequential processing
- [ ] AC-2: Exponential backoff (1s, 2s, 4s, 8s, 5min cap, 10 max attempts)
- [ ] AC-3: AsyncStorage persistence with atomic writes, restore on launch
- [ ] AC-4: Network-aware uploads via netinfo, 300ms debounce
- [ ] AC-5: Status tracking (pending/uploading/processing/completed/failed/permanently_failed)
- [ ] AC-6: Manual retry (preserve count) and cancel actions
- [ ] AC-7: Multipart upload with device auth headers (X-Device-Id, X-Device-Timestamp, X-Device-Signature)

---

_Context generated by Story Context Assembly Workflow_
_Date: 2025-11-23_
