import Image from 'next/image';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { ConfidenceBadge } from '@/components/Evidence/ConfidenceBadge';
import { EvidencePanel } from '@/components/Evidence/EvidencePanel';
import { PartialVideoBanner } from '@/components/Evidence/PartialVideoBanner';
import { PrivacyModeBadge } from '@/components/Evidence/PrivacyModeBadge';
import { ImagePlaceholder } from '@/components/Media/ImagePlaceholder';
import { HashOnlyMediaPlaceholder } from '@/components/Media/HashOnlyMediaPlaceholder';
import { VideoPlayer, VideoPlaceholder } from '@/components/Media/VideoPlayer';
import { apiClient, formatDate, formatDateDayOnly, type ConfidenceLevel, type CheckStatus } from '@/lib/api';
import { mapToEvidenceStatus } from '@/lib/status';

interface VerifyPageProps {
  params: Promise<{ id: string }>;
}

// Demo data for /verify/demo route (works without backend - photo)
const DEMO_CAPTURE: CapturePublicData = {
  capture_id: 'demo',
  confidence_level: 'high',
  captured_at: new Date().toISOString(),
  uploaded_at: new Date().toISOString(),
  location_coarse: 'San Francisco, CA',
  evidence: {
    type: 'photo',
    hardware_attestation: {
      status: 'pass',
      level: 'full',
      verified: true,
      device_model: 'iPhone 15 Pro',
    },
    depth_analysis: {
      status: 'pass',
      is_likely_real_scene: true,
      depth_layers: 42,
      depth_variance: 0.73,
      flat_region_ratio: 0.12,
    },
    metadata: {
      timestamp_valid: true,
      timestamp_delta_seconds: 2,
      model_verified: true,
      model_name: 'iPhone 15 Pro',
      location_available: true,
      location_opted_out: false,
    },
    processing: {
      processed_at: new Date().toISOString(),
      processing_time_ms: 847,
      version: '1.0.0',
    },
  },
  photo_url: '/images/WhatsApp Image 2025-11-23 at 20.24.05.jpeg',
};

// Demo data for /verify/demo-video route (works without backend - video)
const DEMO_VIDEO_CAPTURE: CapturePublicData = {
  capture_id: 'demo-video',
  confidence_level: 'high',
  captured_at: new Date().toISOString(),
  uploaded_at: new Date().toISOString(),
  location_coarse: 'San Francisco, CA',
  evidence: {
    type: 'video',
    duration_ms: 15000,
    frame_count: 450,
    hardware_attestation: {
      status: 'pass',
      level: 'full',
      verified: true,
      device_model: 'iPhone 15 Pro',
      assertion_valid: true,
    },
    depth_analysis: {
      status: 'pass',
      is_likely_real_scene: true,
    },
    hash_chain: {
      status: 'pass',
      verified_frames: 450,
      total_frames: 450,
      chain_intact: true,
      attestation_valid: true,
      verified_duration_ms: 15000,
      checkpoint_verified: false,
    },
    video_depth_analysis: {
      depth_consistency: 0.85,
      motion_coherence: 0.72,
      scene_stability: 0.95,
      is_likely_real_scene: true,
      suspicious_frames: [],
    },
    partial_attestation: {
      is_partial: false,
      verified_frames: 450,
      total_frames: 450,
    },
    metadata: {
      timestamp_valid: true,
      timestamp_delta_seconds: 2,
      model_verified: true,
      model_name: 'iPhone 15 Pro',
      device_model: 'iPhone 15 Pro',
      location_available: true,
      location_opted_out: false,
    },
    processing: {
      processed_at: new Date().toISOString(),
      processing_time_ms: 2150,
      version: '1.0.0',
    },
  },
  video_url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
};

// Demo data for partial video
const DEMO_PARTIAL_VIDEO_CAPTURE: CapturePublicData = {
  capture_id: 'demo-video-partial',
  confidence_level: 'medium',
  captured_at: new Date().toISOString(),
  uploaded_at: new Date().toISOString(),
  location_coarse: 'San Francisco, CA',
  evidence: {
    type: 'video',
    duration_ms: 10000,
    frame_count: 300,
    hardware_attestation: {
      status: 'pass',
      level: 'full',
      verified: true,
      device_model: 'iPhone 15 Pro',
      assertion_valid: true,
    },
    depth_analysis: {
      status: 'unavailable',
    },
    hash_chain: {
      status: 'partial',
      verified_frames: 300,
      total_frames: 450,
      chain_intact: true,
      attestation_valid: true,
      partial_reason: 'Recording interrupted',
      verified_duration_ms: 10000,
      checkpoint_verified: true,
      checkpoint_index: 1,
    },
    partial_attestation: {
      is_partial: true,
      checkpoint_index: 1,
      verified_frames: 300,
      total_frames: 450,
      reason: 'checkpoint_attestation',
    },
    metadata: {
      timestamp_valid: true,
      timestamp_delta_seconds: 3,
      model_verified: true,
      model_name: 'iPhone 15 Pro',
      device_model: 'iPhone 15 Pro',
      location_available: true,
      location_opted_out: false,
    },
    processing: {
      processed_at: new Date().toISOString(),
      processing_time_ms: 1850,
      version: '1.0.0',
    },
  },
  video_url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
};

// Demo data for hash-only capture (Story 8-6)
const DEMO_HASH_ONLY_CAPTURE: CapturePublicData = {
  capture_id: 'demo-hash-only',
  confidence_level: 'high',
  capture_mode: 'hash_only',
  media_stored: false,
  media_hash: 'a1b2c3d4e5f6789abcdef0123456789abcdef0123456789abcdef0123456789a',
  captured_at: new Date().toISOString(),
  uploaded_at: new Date().toISOString(),
  location_coarse: 'San Francisco, CA',
  evidence: {
    type: 'photo',
    analysis_source: 'device',
    hardware_attestation: {
      status: 'pass',
      level: 'full',
      verified: true,
      device_model: 'iPhone 15 Pro',
    },
    depth_analysis: {
      status: 'pass',
      is_likely_real_scene: true,
      depth_layers: 38,
      depth_variance: 0.68,
    },
    metadata_flags: {
      location_included: true,
      location_level: 'coarse',
      timestamp_included: true,
      timestamp_level: 'day_only',
      device_info_included: true,
      device_info_level: 'model_only',
    },
    metadata: {
      timestamp_valid: true,
      timestamp_delta_seconds: 0,
      model_verified: true,
      model_name: 'iPhone 15 Pro',
      location_available: true,
      location_opted_out: false,
    },
    processing: {
      processed_at: new Date().toISOString(),
      processing_time_ms: 125,
      version: '1.0.0',
    },
  },
  // Note: photo_url and video_url intentionally omitted for hash-only
};

// Video-specific evidence types (Story 7-13)
interface HashChainEvidence {
  status: string; // 'pass' | 'partial' | 'fail'
  verified_frames: number;
  total_frames: number;
  chain_intact: boolean;
  attestation_valid: boolean;
  partial_reason?: string;
  verified_duration_ms: number;
  checkpoint_verified: boolean;
  checkpoint_index?: number;
}

interface DepthAnalysisEvidence {
  depth_consistency: number;
  motion_coherence: number;
  scene_stability: number;
  is_likely_real_scene: boolean;
  suspicious_frames: number[];
}

interface PartialAttestationInfo {
  is_partial: boolean;
  checkpoint_index?: number;
  verified_frames: number;
  total_frames: number;
  reason?: string;
}

// Hash-only metadata privacy flags (Story 8-6)
interface MetadataFlags {
  location_included: boolean;
  location_level: 'none' | 'coarse' | 'precise';
  timestamp_included: boolean;
  timestamp_level: 'none' | 'day_only' | 'exact';
  device_info_included: boolean;
  device_info_level: 'none' | 'model_only' | 'full';
}

interface CapturePublicData {
  capture_id: string;
  confidence_level: string;
  captured_at: string;
  uploaded_at: string;
  location_coarse?: string;
  evidence: {
    // Common fields
    type?: string; // 'photo' | 'video'
    hardware_attestation: {
      status: string;
      level?: string;
      verified?: boolean;
      device_model?: string;
      assertion_valid?: boolean; // Video-specific
    };
    // Photo-specific depth analysis
    depth_analysis: {
      status: string;
      is_likely_real_scene?: boolean;
      depth_layers?: number;
      depth_variance?: number;
      flat_region_ratio?: number;
    };
    metadata: {
      timestamp_valid?: boolean;
      timestamp_delta_seconds?: number;
      model_verified?: boolean;
      model_name?: string;
      location_available?: boolean;
      location_opted_out?: boolean;
      device_model?: string; // Video uses metadata.device_model
    };
    processing: {
      processed_at?: string;
      processing_time_ms?: number;
      version?: string;
    };
    // Video-specific fields (Story 7-13)
    hash_chain?: HashChainEvidence;
    video_depth_analysis?: DepthAnalysisEvidence;
    partial_attestation?: PartialAttestationInfo;
    duration_ms?: number;
    frame_count?: number;
    // Hash-only specific fields (Story 8-6)
    analysis_source?: 'server' | 'device';
    metadata_flags?: MetadataFlags;
  };
  photo_url?: string;
  video_url?: string;
  depth_map_url?: string;
  // Hash-only specific fields (Story 8-6)
  capture_mode?: 'full' | 'hash_only';
  media_stored?: boolean;
  media_hash?: string;
}

// Helper to format video duration
function formatDuration(ms: number): string {
  const seconds = ms / 1000;
  return `${seconds.toFixed(1)}s`;
}

// Helper to format depth metrics
function formatDepthMetrics(depth: DepthAnalysisEvidence): string {
  return `Consistency: ${(depth.depth_consistency * 100).toFixed(0)}%, Coherence: ${(depth.motion_coherence * 100).toFixed(0)}%, Stability: ${(depth.scene_stability * 100).toFixed(0)}%`;
}

export default async function VerifyPage({ params }: VerifyPageProps) {
  const { id } = await params;

  // Handle demo routes specially (works without backend)
  let capture: CapturePublicData | null = null;

  if (id === 'demo') {
    capture = DEMO_CAPTURE;
  } else if (id === 'demo-video') {
    capture = DEMO_VIDEO_CAPTURE;
  } else if (id === 'demo-video-partial') {
    capture = DEMO_PARTIAL_VIDEO_CAPTURE;
  } else if (id === 'demo-hash-only') {
    capture = DEMO_HASH_ONLY_CAPTURE;
  } else {
    // Fetch capture data from backend
    const response = await apiClient.getCapturePublic(id);
    capture = response?.data ?? null;
  }

  // Show 404 if capture not found
  if (!capture) {
    notFound();
  }

  // Detect capture type and modes
  const isVideo = capture?.evidence?.type === 'video';
  const isHashOnly = capture?.capture_mode === 'hash_only';
  const hasMedia = capture?.media_stored !== false;
  const mediaType = isVideo ? 'Video' : 'Photo';

  // Build evidence items based on capture type
  let evidenceItems;
  if (capture?.evidence) {
    if (isVideo) {
      // Video evidence items (Story 7-13)
      const items = [
        {
          label: 'Hardware Attestation',
          status: mapToEvidenceStatus(capture.evidence.hardware_attestation?.status),
          value: capture.evidence.hardware_attestation?.device_model || capture.evidence.metadata?.device_model || undefined,
        },
      ];

      // Hash chain integrity (video-specific)
      if (capture.evidence.hash_chain) {
        const hc = capture.evidence.hash_chain;
        const chainStatus = hc.chain_intact ? hc.status : 'fail';
        const framesValue = `${hc.verified_frames.toLocaleString()}/${hc.total_frames.toLocaleString()} frames verified`;
        items.push({
          label: 'Hash Chain Integrity',
          status: mapToEvidenceStatus(chainStatus),
          value: hc.chain_intact ? framesValue : 'Chain broken (tampering detected)',
        });
      }

      // Temporal depth analysis (video-specific)
      if (capture.evidence.video_depth_analysis) {
        const depth = capture.evidence.video_depth_analysis;
        items.push({
          label: 'Temporal Depth Analysis',
          status: depth.is_likely_real_scene ? 'pass' as CheckStatus : 'fail' as CheckStatus,
          value: depth.is_likely_real_scene
            ? `Real 3D scene - ${formatDepthMetrics(depth)}`
            : 'Suspicious scene detected',
        });
      } else {
        items.push({
          label: 'Temporal Depth Analysis',
          status: 'unavailable' as CheckStatus,
          value: 'Not available',
        });
      }

      // Common evidence items
      items.push(
        {
          label: 'Timestamp',
          status: capture.evidence.metadata?.timestamp_valid ? 'pass' as CheckStatus : 'fail' as CheckStatus,
          value: capture.evidence.metadata?.timestamp_delta_seconds !== undefined
            ? `${Math.abs(capture.evidence.metadata.timestamp_delta_seconds)}s delta`
            : undefined,
        },
        {
          label: 'Device Model',
          status: capture.evidence.metadata?.model_verified ? 'pass' as CheckStatus : 'unavailable' as CheckStatus,
          value: capture.evidence.metadata?.model_name || capture.evidence.metadata?.device_model || undefined,
        },
        {
          label: 'Location',
          status: capture.evidence.metadata?.location_available ? 'pass' as CheckStatus : 'unavailable' as CheckStatus,
          value: capture.location_coarse || (capture.evidence.metadata?.location_opted_out ? 'Opted out' : undefined),
        }
      );

      evidenceItems = items;
    } else {
      // Photo evidence items (existing logic + hash-only support)
      const isDeviceAnalysis = capture.evidence.analysis_source === 'device';

      evidenceItems = [
        {
          label: 'Hardware Attestation',
          status: mapToEvidenceStatus(capture.evidence.hardware_attestation?.status),
          value: capture.evidence.hardware_attestation?.device_model || undefined,
        },
        {
          label: isDeviceAnalysis ? 'LiDAR Depth Analysis (Device)' : 'LiDAR Depth Analysis',
          status: mapToEvidenceStatus(capture.evidence.depth_analysis?.status),
          value: capture.evidence.depth_analysis?.is_likely_real_scene
            ? (isDeviceAnalysis ? 'Real 3D scene - Device analysis' : 'Real 3D scene detected')
            : 'Analysis complete',
        },
        {
          label: 'Timestamp',
          status: capture.evidence.metadata?.timestamp_valid ? 'pass' as CheckStatus : 'fail' as CheckStatus,
          value: capture.evidence.metadata?.timestamp_delta_seconds !== undefined
            ? `${Math.abs(capture.evidence.metadata.timestamp_delta_seconds)}s delta`
            : undefined,
        },
        {
          label: 'Device Model',
          status: capture.evidence.metadata?.model_verified ? 'pass' as CheckStatus : 'unavailable' as CheckStatus,
          value: capture.evidence.metadata?.model_name || undefined,
        },
        {
          label: 'Location',
          status: capture.evidence.metadata?.location_available ? 'pass' as CheckStatus : 'unavailable' as CheckStatus,
          value: capture.location_coarse || (capture.evidence.metadata?.location_opted_out ? 'Opted out' : undefined),
        },
      ];
    }
  }

  // Video-specific data
  const isPartialVideo = isVideo && capture?.evidence?.partial_attestation?.is_partial;
  const partialAttestation = capture?.evidence?.partial_attestation;
  const hashChain = capture?.evidence?.hash_chain;
  const durationMs = capture?.evidence?.duration_ms ?? 0;
  const frameCount = capture?.evidence?.frame_count ?? 0;

  return (
    <div className="min-h-screen bg-zinc-50 dark:bg-black">
      {/* Header */}
      <header className="w-full border-b border-zinc-200 dark:border-zinc-800">
        <div className="mx-auto max-w-4xl px-4 sm:px-6 lg:px-8 py-4 sm:py-6">
          <div className="flex items-center justify-between">
            <Link
              href="/"
              className="text-xl sm:text-2xl font-bold tracking-tight text-black dark:text-white hover:text-zinc-600 dark:hover:text-zinc-300 transition-colors"
            >
              rial.
            </Link>
            <span className="text-xs sm:text-sm text-zinc-500 dark:text-zinc-400">
              {mediaType} Verification
            </span>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="mx-auto max-w-4xl px-4 sm:px-6 lg:px-8 py-8 sm:py-12">
        <div className="flex flex-col gap-6 sm:gap-8">
          {/* Page Title */}
          <div>
            <h1 className="text-2xl sm:text-3xl font-bold tracking-tight text-black dark:text-white">
              {mediaType} Verification
            </h1>
            <p className="mt-2 text-sm sm:text-base text-zinc-600 dark:text-zinc-400">
              Capture ID: <code className="font-mono text-zinc-800 dark:text-zinc-300">{id}</code>
            </p>
          </div>

          {/* Partial Video Banner (Story 7-13) */}
          {isPartialVideo && partialAttestation && hashChain && (
            <PartialVideoBanner
              verifiedFrames={partialAttestation.verified_frames}
              totalFrames={partialAttestation.total_frames}
              verifiedDurationMs={hashChain.verified_duration_ms}
              totalDurationMs={durationMs}
              checkpointIndex={partialAttestation.checkpoint_index}
            />
          )}

          {/* Main Results Card */}
          <div className="rounded-xl border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 overflow-hidden">
            {/* Results Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-0">
              {/* Media Section */}
              <div className="p-4 sm:p-6 md:border-r border-b md:border-b-0 border-zinc-200 dark:border-zinc-800">
                <h2 className="text-sm font-semibold text-zinc-900 dark:text-white uppercase tracking-wide mb-4">
                  Captured {mediaType}
                </h2>
                {isHashOnly || !hasMedia ? (
                  // Hash-only placeholder (Story 8-6)
                  <HashOnlyMediaPlaceholder aspectRatio={isVideo ? '16:9' : '4:3'} />
                ) : isVideo ? (
                  // Video Player (Story 7-13)
                  capture?.video_url ? (
                    <VideoPlayer src={capture.video_url} aspectRatio="16:9" />
                  ) : (
                    <VideoPlaceholder aspectRatio="16:9" />
                  )
                ) : (
                  // Photo Image (existing)
                  capture?.photo_url ? (
                    <div className="relative w-full aspect-[4/3]">
                      <Image
                        src={capture.photo_url}
                        alt="Captured photo"
                        fill
                        className="rounded-lg object-cover"
                        unoptimized
                      />
                    </div>
                  ) : (
                    <ImagePlaceholder aspectRatio="4:3" />
                  )
                )}
              </div>

              {/* Summary Section */}
              <div className="p-4 sm:p-6">
                <h2 className="text-sm font-semibold text-zinc-900 dark:text-white uppercase tracking-wide mb-4">
                  Verification Summary
                </h2>

                {/* Confidence Badge and Privacy Mode Badge */}
                <div className="mb-6" data-testid="confidence-score">
                  <p className="text-xs text-zinc-500 dark:text-zinc-400 mb-2">
                    Confidence Level
                  </p>
                  <div className="flex flex-wrap gap-2" data-testid="verification-status">
                    <ConfidenceBadge level={capture?.confidence_level as ConfidenceLevel || 'pending'} />
                    {isHashOnly && <PrivacyModeBadge />}
                  </div>
                </div>

                {/* Metadata */}
                <div className="space-y-4">
                  {/* Video Duration (Story 7-13) */}
                  {isVideo && durationMs > 0 && (
                    <div>
                      <p className="text-xs text-zinc-500 dark:text-zinc-400 mb-1">
                        Duration
                      </p>
                      <p className="text-sm text-zinc-700 dark:text-zinc-300">
                        {isPartialVideo && partialAttestation ? (
                          `${formatDuration(hashChain?.verified_duration_ms ?? 0)} of ${formatDuration(durationMs)} (partial)`
                        ) : (
                          formatDuration(durationMs)
                        )}
                        {frameCount > 0 && (
                          <span className="text-zinc-500 dark:text-zinc-400 ml-2">
                            ({frameCount.toLocaleString()} frames)
                          </span>
                        )}
                      </p>
                    </div>
                  )}

                  <div>
                    <p className="text-xs text-zinc-500 dark:text-zinc-400 mb-1">
                      Captured At
                    </p>
                    <p className="text-sm text-zinc-700 dark:text-zinc-300">
                      {/* Check metadata_flags.timestamp_level for privacy mode (AC4) */}
                      {capture?.evidence?.metadata_flags?.timestamp_level === 'none' ? (
                        <span className="text-zinc-400 dark:text-zinc-500 italic">
                          Not included
                        </span>
                      ) : capture?.evidence?.metadata_flags?.timestamp_level === 'day_only' && capture?.captured_at ? (
                        formatDateDayOnly(capture.captured_at)
                      ) : capture?.captured_at ? (
                        formatDate(capture.captured_at)
                      ) : (
                        <span className="text-zinc-400 dark:text-zinc-500 italic">
                          Not available
                        </span>
                      )}
                    </p>
                  </div>

                  <div>
                    <p className="text-xs text-zinc-500 dark:text-zinc-400 mb-1">
                      Location
                    </p>
                    <p className="text-sm text-zinc-700 dark:text-zinc-300">
                      {/* Check metadata_flags.location_level for privacy mode (AC4) */}
                      {capture?.evidence?.metadata_flags?.location_level === 'none' ? (
                        <span className="text-zinc-400 dark:text-zinc-500 italic">
                          Not included
                        </span>
                      ) : capture?.evidence?.metadata_flags?.location_level === 'coarse' && capture?.location_coarse ? (
                        capture.location_coarse
                      ) : capture?.location_coarse ? (
                        capture.location_coarse
                      ) : capture?.evidence?.metadata?.location_opted_out ? (
                        <span className="text-zinc-400 dark:text-zinc-500 italic">
                          Location opted out
                        </span>
                      ) : (
                        <span className="text-zinc-400 dark:text-zinc-500 italic">
                          Not available
                        </span>
                      )}
                    </p>
                  </div>

                  <div>
                    <p className="text-xs text-zinc-500 dark:text-zinc-400 mb-1">
                      Device
                    </p>
                    <p className="text-sm text-zinc-700 dark:text-zinc-300">
                      {/* Check metadata_flags.device_info_level for privacy mode (AC4) */}
                      {capture?.evidence?.metadata_flags?.device_info_level === 'none' ? (
                        <span className="text-zinc-400 dark:text-zinc-500 italic">
                          Not included
                        </span>
                      ) : capture?.evidence?.metadata?.model_name || capture?.evidence?.hardware_attestation?.device_model || (
                        <span className="text-zinc-400 dark:text-zinc-500 italic">
                          Not available
                        </span>
                      )}
                    </p>
                  </div>
                </div>
              </div>
            </div>

            {/* Status Message */}
            {!capture && (
              <div className="px-4 sm:px-6 py-4 bg-zinc-50 dark:bg-zinc-900/50 border-t border-zinc-200 dark:border-zinc-800" data-testid="processing-indicator">
                <p className="text-sm text-center text-zinc-500 dark:text-zinc-400">
                  Capture not found or still processing
                </p>
              </div>
            )}
          </div>

          {/* Evidence Panel */}
          {evidenceItems ? (
            <EvidencePanel items={evidenceItems} defaultExpanded={true} />
          ) : (
            <EvidencePanel />
          )}

          {/* Back Link */}
          <div className="text-center pt-4">
            <Link
              href="/"
              className="inline-flex items-center gap-2 text-sm font-medium text-blue-600 dark:text-blue-400 hover:text-blue-700 dark:hover:text-blue-300 transition-colors"
            >
              <svg
                className="h-4 w-4"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
                aria-hidden="true"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M15 19l-7-7 7-7"
                />
              </svg>
              Back to Home
            </Link>
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="w-full border-t border-zinc-200 dark:border-zinc-800 mt-auto">
        <div className="mx-auto max-w-4xl px-4 sm:px-6 lg:px-8 py-6">
          <p className="text-center text-xs text-zinc-500 dark:text-zinc-400">
            rial. - Authentic photo verification powered by hardware attestation and AI
          </p>
        </div>
      </footer>
    </div>
  );
}
