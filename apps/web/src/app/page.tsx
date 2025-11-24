import Link from 'next/link';
import { FileDropzone } from '@/components/Upload/FileDropzone';

export default function Home() {
  return (
    <div className="min-h-screen bg-zinc-50 dark:bg-black">
      {/* Header */}
      <header className="w-full border-b border-zinc-200 dark:border-zinc-800">
        <div className="mx-auto max-w-4xl px-4 sm:px-6 lg:px-8 py-4 sm:py-6">
          <div className="flex items-center justify-between">
            <h1 className="text-xl sm:text-2xl font-bold tracking-tight text-black dark:text-white">
              rial.
            </h1>
            <span className="text-xs sm:text-sm text-zinc-500 dark:text-zinc-400">
              Photo Verification
            </span>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="mx-auto max-w-4xl px-4 sm:px-6 lg:px-8 py-8 sm:py-12 lg:py-16">
        <div className="flex flex-col items-center gap-8 sm:gap-12">
          {/* Hero Section */}
          <div className="text-center">
            <h2 className="text-2xl sm:text-3xl lg:text-4xl font-bold tracking-tight text-black dark:text-white">
              Verify Photo Authenticity
            </h2>
            <p className="mt-4 max-w-xl text-base sm:text-lg text-zinc-600 dark:text-zinc-400">
              Upload a photo to check if it was captured with rial. and view
              its verification evidence including hardware attestation, LiDAR depth
              analysis, and cryptographic signatures.
            </p>
          </div>

          {/* File Upload Section */}
          <div className="w-full max-w-xl">
            <FileDropzone />
          </div>

          {/* Info Section */}
          <div className="w-full max-w-xl">
            <div className="rounded-xl border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 p-6">
              <h3 className="text-sm font-semibold text-zinc-900 dark:text-white uppercase tracking-wide">
                What We Verify
              </h3>
              <ul className="mt-4 space-y-3 text-sm text-zinc-600 dark:text-zinc-400">
                <li className="flex items-start gap-3">
                  <svg
                    className="h-5 w-5 flex-shrink-0 text-green-500 dark:text-green-400"
                    fill="currentColor"
                    viewBox="0 0 20 20"
                    aria-hidden="true"
                  >
                    <path
                      fillRule="evenodd"
                      d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z"
                      clipRule="evenodd"
                    />
                  </svg>
                  <span>
                    <strong className="text-zinc-900 dark:text-white">Hardware Attestation</strong>
                    {' - '}Secure Enclave cryptographic proof from iPhone
                  </span>
                </li>
                <li className="flex items-start gap-3">
                  <svg
                    className="h-5 w-5 flex-shrink-0 text-green-500 dark:text-green-400"
                    fill="currentColor"
                    viewBox="0 0 20 20"
                    aria-hidden="true"
                  >
                    <path
                      fillRule="evenodd"
                      d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z"
                      clipRule="evenodd"
                    />
                  </svg>
                  <span>
                    <strong className="text-zinc-900 dark:text-white">LiDAR Depth Analysis</strong>
                    {' - '}3D scene verification to detect screen captures
                  </span>
                </li>
                <li className="flex items-start gap-3">
                  <svg
                    className="h-5 w-5 flex-shrink-0 text-green-500 dark:text-green-400"
                    fill="currentColor"
                    viewBox="0 0 20 20"
                    aria-hidden="true"
                  >
                    <path
                      fillRule="evenodd"
                      d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z"
                      clipRule="evenodd"
                    />
                  </svg>
                  <span>
                    <strong className="text-zinc-900 dark:text-white">C2PA Signatures</strong>
                    {' - '}Industry-standard content authenticity credentials
                  </span>
                </li>
              </ul>
            </div>
          </div>

          {/* Demo Link */}
          <div className="text-center">
            <p className="text-sm text-zinc-500 dark:text-zinc-400 mb-3">
              Want to see an example?
            </p>
            <Link
              href="/verify/demo"
              className="inline-flex items-center gap-2 text-sm font-medium text-blue-600 dark:text-blue-400 hover:text-blue-700 dark:hover:text-blue-300 transition-colors"
            >
              View Demo Verification
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
