// API Types
export type { ApiResponse, ApiError } from './types/api';

// Evidence Types
export type {
  ConfidenceLevel,
  EvidenceStatus,
  HardwareAttestation,
  DepthAnalysis,
  Evidence,
} from './types/evidence';

// Capture Types
export type {
  Capture,
  CameraIntrinsics,
  DepthFrame,
  DepthColormap,
  DepthOverlayConfig,
  RawCapture,
  CaptureErrorCode,
  CaptureError,
  CaptureLocation,
  LocationErrorCode,
  LocationError,
  AssertionMetadata,
  CaptureAssertion,
  CaptureAssertionErrorCode,
  CaptureAssertionError,
  // Story 3.5: Local Processing Types
  CaptureStatus,
  CaptureMetadata,
  ProcessedCapture,
  ProcessingErrorCode,
  ProcessingError,
} from './types/capture';

// Device Types
export type {
  Platform,
  DeviceCapabilities,
  DeviceRegistrationState,
  KeyGenerationStatus,
  AttestationStatus,
  ChallengeResponse,
} from './types/device';

// Upload Queue Types (Story 4.2)
export type {
  QueuedCaptureStatus,
  UploadErrorCode,
  UploadError,
  QueuedCapture,
  UploadQueueState,
  UploadQueueActions,
  CaptureUploadResponse,
  RetryConfig,
} from './types/upload';
export { DEFAULT_RETRY_CONFIG } from './types/upload';
