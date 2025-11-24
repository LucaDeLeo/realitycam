import Image from 'next/image';
import Link from 'next/link';
import { ConfidenceBadge } from '@/components/Evidence/ConfidenceBadge';
import { EvidencePanel } from '@/components/Evidence/EvidencePanel';
import { ImagePlaceholder } from '@/components/Media/ImagePlaceholder';
import { apiClient, formatDate, type ConfidenceLevel, type CheckStatus } from '@/lib/api';

interface VerifyPageProps {
  params: Promise<{ id: string }>;
}

export default async function VerifyPage({ params }: VerifyPageProps) {
  const { id } = await params;

  // Fetch capture data from backend
  const response = await apiClient.getCapturePublic(id);
  const capture = response?.data;

  // Map evidence status to CheckStatus
  const getCheckStatus = (status: string | undefined): CheckStatus => {
    if (status === 'pass' || status === 'verified') return 'pass';
    if (status === 'fail' || status === 'failed') return 'fail';
    return 'unavailable';
  };

  // Build evidence items from capture data
  const evidenceItems = capture?.evidence ? [
    {
      label: 'Hardware Attestation',
      status: getCheckStatus(capture.evidence.hardware_attestation?.status),
      value: capture.evidence.hardware_attestation?.device_model || undefined,
    },
    {
      label: 'LiDAR Depth Analysis',
      status: getCheckStatus(capture.evidence.depth_analysis?.status),
      value: capture.evidence.depth_analysis?.is_likely_real_scene ? 'Real 3D scene detected' : 'Analysis complete',
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
  ] : undefined;

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
              Photo Verification
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
              Photo Verification
            </h1>
            <p className="mt-2 text-sm sm:text-base text-zinc-600 dark:text-zinc-400">
              Capture ID: <code className="font-mono text-zinc-800 dark:text-zinc-300">{id}</code>
            </p>
          </div>

          {/* Main Results Card */}
          <div className="rounded-xl border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 overflow-hidden">
            {/* Results Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-0">
              {/* Image Section */}
              <div className="p-4 sm:p-6 md:border-r border-b md:border-b-0 border-zinc-200 dark:border-zinc-800">
                <h2 className="text-sm font-semibold text-zinc-900 dark:text-white uppercase tracking-wide mb-4">
                  Captured Image
                </h2>
                {capture?.photo_url ? (
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
                )}
              </div>

              {/* Summary Section */}
              <div className="p-4 sm:p-6">
                <h2 className="text-sm font-semibold text-zinc-900 dark:text-white uppercase tracking-wide mb-4">
                  Verification Summary
                </h2>

                {/* Confidence Badge */}
                <div className="mb-6" data-testid="confidence-score">
                  <p className="text-xs text-zinc-500 dark:text-zinc-400 mb-2">
                    Confidence Level
                  </p>
                  <div data-testid="verification-status">
                    <ConfidenceBadge level={capture?.confidence_level as ConfidenceLevel || 'pending'} />
                  </div>
                </div>

                {/* Metadata */}
                <div className="space-y-4">
                  <div>
                    <p className="text-xs text-zinc-500 dark:text-zinc-400 mb-1">
                      Captured At
                    </p>
                    <p className="text-sm text-zinc-700 dark:text-zinc-300">
                      {capture?.captured_at ? (
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
                      {capture?.location_coarse ? (
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
                      {capture?.evidence?.metadata?.model_name || capture?.evidence?.hardware_attestation?.device_model || (
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
