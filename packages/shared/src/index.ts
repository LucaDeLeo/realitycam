// API Types
export type { ApiResponse, ApiError } from './types/api';

// Evidence Types
export type {
  ConfidenceLevel,
  EvidenceStatus,
  HardwareAttestation,
  DepthAnalysis,
  MetadataEvidence,
  ProcessingInfo,
  Evidence,
  MetadataFlags, // Story 8-7
  TemporalDepthAnalysis, // Story 8-8
  HashChainEvidence, // Story 8-8
  // Detection Types (Story 11-1)
  DetectionMethodStatus,
  DetectionMethodResult,
  AggregatedConfidence,
  LidarDepthDetails,
  MoireScreenType,
  MoireDetectionResult,
  TextureClassification,
  TextureClassificationResult,
  ArtifactAnalysisResult,
  DetectionResults,
  // Cross-Validation Types (Story 11-2)
  CrossValidationResult,
  PairwiseConsistency,
  TemporalConsistency,
  TemporalAnomaly,
  ConfidenceInterval,
  AnomalyReport,
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
  // Offline Storage Types (Story 4.3)
  CaptureStorageLocation,
  StorageQuotaStatus,
  OfflineCaptureEncryption,
  OfflineCaptureMetadata,
  StorageQuotaInfo,
  CaptureIndexEntry,
  OfflineQueuedCapture,
} from './types/upload';
export { DEFAULT_RETRY_CONFIG, STORAGE_QUOTA_CONFIG } from './types/upload';

// Utilities
export {
  bytesToBase64,
  base64ToBytes,
  uint8ArrayToBase64,
  base64ToUint8Array,
} from './utils/base64';
