import Link from 'next/link';
import type { Metadata } from 'next';
import {
  ExpandableSection,
  TableOfContents,
  TrustModelSection,
  LidarSection,
  MoireSection,
  TextureSection,
  ArtifactsSection,
  CrossValidationMethodSection,
  PlatformSection,
  ConfidenceSection,
  LimitationsSection,
  FAQSection,
} from '@/components/Methodology';

/**
 * SEO Metadata for methodology page (AC #1)
 */
export const metadata: Metadata = {
  title: 'How rial. Verification Works | Methodology',
  description: 'Learn how rial. verifies photo and video authenticity using LiDAR depth analysis, hardware attestation, and multi-signal detection. Understand our attestation-first trust model.',
  openGraph: {
    title: 'How rial. Verification Works',
    description: 'Understanding rial.\'s attestation-first trust model for photo and video authenticity verification.',
    type: 'article',
    url: '/methodology',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'How rial. Verification Works',
    description: 'Learn about rial.\'s attestation-first trust model and multi-signal detection methodology.',
  },
  alternates: {
    canonical: '/methodology',
  },
};

/** Table of contents navigation items */
const TOC_ITEMS = [
  { id: 'overview', label: 'Overview' },
  { id: 'trust-model', label: 'Trust Model' },
  { id: 'detection-methods', label: 'Detection Methods' },
  { id: 'lidar', label: 'LiDAR Depth', indent: true },
  { id: 'moire', label: 'Moire Detection', indent: true },
  { id: 'texture', label: 'Texture Analysis', indent: true },
  { id: 'artifacts', label: 'Artifact Detection', indent: true },
  { id: 'cross-validation', label: 'Cross-Validation' },
  { id: 'platforms', label: 'Platforms & Attestation' },
  { id: 'confidence', label: 'Confidence Calculation' },
  { id: 'limitations', label: 'Limitations' },
  { id: 'faq', label: 'FAQ' },
];

/**
 * MethodologyPage - Explains how rial. verification works
 *
 * Story 11-4: Methodology Explainer Page
 * - Progressive disclosure with expandable sections
 * - Table of contents navigation (desktop)
 * - Accessible and responsive design
 */
export default function MethodologyPage() {
  return (
    <div className="min-h-screen bg-zinc-50 dark:bg-black">
      {/* Header */}
      <header className="w-full border-b border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-4 sm:py-6">
          <div className="flex items-center justify-between">
            <Link
              href="/"
              className="text-xl sm:text-2xl font-bold tracking-tight text-black dark:text-white hover:text-zinc-600 dark:hover:text-zinc-300 transition-colors"
            >
              rial.
            </Link>
            <span className="text-xs sm:text-sm text-zinc-500 dark:text-zinc-400">
              Methodology
            </span>
          </div>
        </div>
      </header>

      {/* Main Content with Sidebar */}
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8 sm:py-12">
        <div className="lg:grid lg:grid-cols-[1fr_250px] lg:gap-12">
          {/* Main Content */}
          <main>
            {/* Page Title and Executive Summary */}
            <div id="overview" className="mb-12 scroll-mt-20">
              <h1 className="text-3xl sm:text-4xl font-bold tracking-tight text-black dark:text-white mb-4">
                How rial. Verification Works
              </h1>

              {/* Executive Summary - always visible */}
              <div className="bg-white dark:bg-zinc-900 rounded-xl border border-zinc-200 dark:border-zinc-800 p-6 mb-6">
                <p className="text-lg text-zinc-700 dark:text-zinc-300 leading-relaxed">
                  rial. verifies photo and video authenticity using an{' '}
                  <strong className="text-zinc-900 dark:text-white">attestation-first trust model</strong>.
                </p>
                <p className="text-zinc-600 dark:text-zinc-400 mt-4 leading-relaxed">
                  Hardware attestation (iOS Secure Enclave, Android TEE/StrongBox) proves the capture
                  device is genuine. LiDAR depth analysis proves the camera was pointed at a real 3D
                  scene, not a screen or print. Supporting detection methods (Moire, texture, artifacts)
                  provide defense-in-depth.
                </p>
              </div>

              {/* Quick visual - trust hierarchy */}
              <div className="bg-zinc-100 dark:bg-zinc-800/50 rounded-xl p-6 mb-6">
                <h2 className="text-sm font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wide mb-4">
                  Trust Hierarchy at a Glance
                </h2>
                <div className="flex flex-col sm:flex-row gap-3">
                  <div className="flex-1 bg-green-100 dark:bg-green-900/30 border-l-4 border-green-500 p-3 rounded-r">
                    <p className="text-xs text-green-600 dark:text-green-400 font-medium">PRIMARY</p>
                    <p className="text-sm text-green-800 dark:text-green-300 font-semibold">Hardware Attestation</p>
                  </div>
                  <div className="flex-1 bg-blue-100 dark:bg-blue-900/30 border-l-4 border-blue-500 p-3 rounded-r">
                    <p className="text-xs text-blue-600 dark:text-blue-400 font-medium">STRONG</p>
                    <p className="text-sm text-blue-800 dark:text-blue-300 font-semibold">Physical Depth Signals</p>
                  </div>
                  <div className="flex-1 bg-yellow-100 dark:bg-yellow-900/30 border-l-4 border-yellow-500 p-3 rounded-r">
                    <p className="text-xs text-yellow-600 dark:text-yellow-400 font-medium">SUPPORTING</p>
                    <p className="text-sm text-yellow-800 dark:text-yellow-300 font-semibold">Detection Algorithms</p>
                  </div>
                </div>
              </div>
            </div>

            {/* Expandable Sections */}
            <div className="space-y-4">
              {/* Trust Model */}
              <ExpandableSection
                id="trust-model"
                title="Attestation-First Trust Model"
                summary="Why hardware attestation is the primary trust signal"
                icon={
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                  </svg>
                }
              >
                <TrustModelSection />
              </ExpandableSection>

              {/* Detection Methods Header */}
              <div id="detection-methods" className="pt-6 scroll-mt-20">
                <h2 className="text-xl font-semibold text-zinc-900 dark:text-white mb-4">
                  Detection Methods
                </h2>
                <p className="text-zinc-600 dark:text-zinc-400 mb-4">
                  Multiple independent methods analyze each capture. Click to expand details.
                </p>
              </div>

              {/* LiDAR */}
              <ExpandableSection
                id="lidar"
                title="LiDAR Depth Analysis"
                summary="Primary physical signal for iOS Pro devices"
                headingLevel="h3"
                icon={
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                  </svg>
                }
              >
                <LidarSection />
              </ExpandableSection>

              {/* Moire */}
              <ExpandableSection
                id="moire"
                title="Moire Pattern Detection"
                summary="Screen pixel interference detection via FFT"
                headingLevel="h3"
                icon={
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6zM16 13a1 1 0 011-1h2a1 1 0 011 1v6a1 1 0 01-1 1h-2a1 1 0 01-1-1v-6z" />
                  </svg>
                }
              >
                <MoireSection />
              </ExpandableSection>

              {/* Texture */}
              <ExpandableSection
                id="texture"
                title="Texture Classification"
                summary="ML-based material analysis"
                headingLevel="h3"
                icon={
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                  </svg>
                }
              >
                <TextureSection />
              </ExpandableSection>

              {/* Artifacts */}
              <ExpandableSection
                id="artifacts"
                title="Artifact Detection"
                summary="PWM, specular, and halftone pattern analysis"
                headingLevel="h3"
                icon={
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                  </svg>
                }
              >
                <ArtifactsSection />
              </ExpandableSection>

              {/* Cross-Validation */}
              <ExpandableSection
                id="cross-validation"
                title="Cross-Validation"
                summary="How methods are checked against each other"
                icon={
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
                  </svg>
                }
              >
                <CrossValidationMethodSection />
              </ExpandableSection>

              {/* Platforms */}
              <ExpandableSection
                id="platforms"
                title="Platforms & Attestation"
                summary="iOS Secure Enclave, Android StrongBox/TEE"
                icon={
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z" />
                  </svg>
                }
              >
                <PlatformSection />
              </ExpandableSection>

              {/* Confidence Calculation */}
              <ExpandableSection
                id="confidence"
                title="Confidence Calculation"
                summary="How scores are weighted and combined"
                icon={
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 7h6m0 10v-3m-3 3h.01M9 17h.01M9 14h.01M12 14h.01M15 11h.01M12 11h.01M9 11h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z" />
                  </svg>
                }
              >
                <ConfidenceSection />
              </ExpandableSection>

              {/* Limitations */}
              <ExpandableSection
                id="limitations"
                title="Known Limitations & Threat Model"
                summary="What we can and cannot detect"
                icon={
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                  </svg>
                }
              >
                <LimitationsSection />
              </ExpandableSection>

              {/* FAQ */}
              <section id="faq" className="pt-8 scroll-mt-20">
                <h2 className="text-xl font-semibold text-zinc-900 dark:text-white mb-4">
                  Frequently Asked Questions
                </h2>
                <FAQSection />
              </section>
            </div>

            {/* Back Link */}
            <div className="mt-12 pt-8 border-t border-zinc-200 dark:border-zinc-800">
              <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
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
                <Link
                  href="/verify/demo"
                  className="inline-flex items-center gap-2 text-sm font-medium text-zinc-600 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-white transition-colors"
                >
                  See a demo verification
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
                      d="M9 5l7 7-7 7"
                    />
                  </svg>
                </Link>
              </div>
            </div>
          </main>

          {/* Sidebar - Table of Contents (desktop only) */}
          <aside className="hidden lg:block">
            <TableOfContents items={TOC_ITEMS} />
          </aside>
        </div>
      </div>

      {/* Footer */}
      <footer className="w-full border-t border-zinc-200 dark:border-zinc-800 mt-auto">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-6">
          <p className="text-center text-xs text-zinc-500 dark:text-zinc-400">
            rial. - Authentic photo verification powered by hardware attestation and AI
          </p>
        </div>
      </footer>
    </div>
  );
}
