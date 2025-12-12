/**
 * MoireSection - Explains Moire pattern detection methodology
 *
 * Content from PRD lines 347: Moire Pattern Detection using 2D FFT
 * frequency analysis to detect screen pixel grid interference.
 */

/**
 * MoirePatternDiagram - Visual explanation of Moire patterns
 */
function MoirePatternDiagram() {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 my-4">
      {/* Screen pixels */}
      <div className="border border-zinc-200 dark:border-zinc-700 rounded-lg p-4 text-center">
        <div className="h-20 mb-3 flex items-center justify-center" aria-hidden="true">
          <div className="grid grid-cols-6 gap-0.5">
            {Array.from({ length: 36 }).map((_, i) => (
              <div key={i} className="w-2 h-2 bg-zinc-400 dark:bg-zinc-500" />
            ))}
          </div>
        </div>
        <p className="text-sm font-medium text-zinc-900 dark:text-white">Screen Pixel Grid</p>
        <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">Regular pattern of pixels</p>
      </div>

      {/* Plus sign */}
      <div className="hidden sm:flex items-center justify-center text-3xl text-zinc-400 dark:text-zinc-500" aria-hidden="true">
        +
      </div>

      {/* Camera sensor */}
      <div className="border border-zinc-200 dark:border-zinc-700 rounded-lg p-4 text-center">
        <div className="h-20 mb-3 flex items-center justify-center" aria-hidden="true">
          <div className="grid grid-cols-5 gap-1">
            {Array.from({ length: 25 }).map((_, i) => (
              <div key={i} className="w-2.5 h-2.5 rounded-full bg-blue-400 dark:bg-blue-500" />
            ))}
          </div>
        </div>
        <p className="text-sm font-medium text-zinc-900 dark:text-white">Camera Sensor</p>
        <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">Different sampling frequency</p>
      </div>

      {/* Equals */}
      <div className="sm:col-span-3 flex items-center justify-center py-2" aria-hidden="true">
        <span className="text-2xl text-zinc-400 dark:text-zinc-500">=</span>
      </div>

      {/* Moire pattern result */}
      <div className="sm:col-span-3 border border-yellow-300 dark:border-yellow-700 rounded-lg p-4 bg-yellow-50 dark:bg-yellow-900/20">
        <div className="flex items-center gap-2 mb-2">
          <span className="w-3 h-3 rounded-full bg-yellow-500" aria-hidden="true" />
          <p className="font-semibold text-yellow-800 dark:text-yellow-300">Moire Interference Pattern</p>
        </div>
        <p className="text-sm text-yellow-700 dark:text-yellow-400">
          When two regular grids overlap at slightly different frequencies, they create
          visible interference patterns - wavy lines or rainbow effects. These patterns
          are detectable in the frequency domain using FFT analysis.
        </p>
      </div>
    </div>
  );
}

/**
 * MoireSection - Main content component
 */
export function MoireSection() {
  return (
    <div className="space-y-6">
      {/* What are Moire patterns */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          What are Moire Patterns?
        </h3>
        <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed">
          Moire patterns are interference patterns that occur when two regular grids overlap.
          When you photograph a screen, the camera sensor&apos;s pixel grid interacts with the
          screen&apos;s pixel grid, creating distinctive wave-like patterns that are invisible
          to the human eye but detectable through signal analysis.
        </p>
        <MoirePatternDiagram />
      </div>

      {/* How detection works */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          How Detection Works
        </h3>
        <div className="space-y-4">
          <div className="flex gap-4">
            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-blue-100 dark:bg-blue-900/50 flex items-center justify-center">
              <span className="text-sm font-semibold text-blue-600 dark:text-blue-400">1</span>
            </div>
            <div>
              <h4 className="font-medium text-zinc-900 dark:text-white">2D Fast Fourier Transform (FFT)</h4>
              <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">
                The image is converted from spatial domain to frequency domain using FFT.
                This reveals periodic patterns that are not visible to the eye.
              </p>
            </div>
          </div>

          <div className="flex gap-4">
            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-blue-100 dark:bg-blue-900/50 flex items-center justify-center">
              <span className="text-sm font-semibold text-blue-600 dark:text-blue-400">2</span>
            </div>
            <div>
              <h4 className="font-medium text-zinc-900 dark:text-white">Frequency Peak Detection</h4>
              <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">
                Screen pixels create characteristic peaks in the frequency spectrum at
                specific intervals. The algorithm searches for these telltale peaks.
              </p>
            </div>
          </div>

          <div className="flex gap-4">
            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-blue-100 dark:bg-blue-900/50 flex items-center justify-center">
              <span className="text-sm font-semibold text-blue-600 dark:text-blue-400">3</span>
            </div>
            <div>
              <h4 className="font-medium text-zinc-900 dark:text-white">Confidence Scoring</h4>
              <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">
                Based on peak intensity and pattern matching, a confidence score indicates
                how likely the image contains screen capture artifacts.
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Understanding the score */}
      <div className="bg-green-50 dark:bg-green-900/20 border-l-4 border-green-500 p-4 rounded-r-lg">
        <h3 className="font-semibold text-green-800 dark:text-green-300 mb-2">
          Understanding the Score
        </h3>
        <p className="text-sm text-green-700 dark:text-green-400 mb-3">
          For Moire detection, <strong>&quot;not detected&quot; (0%) is GOOD</strong>. This means:
        </p>
        <ul className="text-sm text-green-700 dark:text-green-400 space-y-1">
          <li>- No screen pixel patterns were found</li>
          <li>- The image likely was not captured from a screen</li>
          <li>- This supports authenticity (when combined with other signals)</li>
        </ul>
        <p className="text-sm text-green-700 dark:text-green-400 mt-3">
          A high Moire score (e.g., 80%) indicates strong evidence of screen capture.
        </p>
      </div>

      {/* Detection capabilities */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          Detection Capabilities
        </h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-3 rounded-lg">
            <p className="text-sm font-medium text-zinc-900 dark:text-white">LCD Screens</p>
            <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">
              Strong detection - regular RGB subpixel pattern
            </p>
          </div>
          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-3 rounded-lg">
            <p className="text-sm font-medium text-zinc-900 dark:text-white">OLED Screens</p>
            <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">
              Good detection - PenTile and other patterns
            </p>
          </div>
          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-3 rounded-lg">
            <p className="text-sm font-medium text-zinc-900 dark:text-white">High-Refresh Displays</p>
            <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">
              Detectable - 90Hz/120Hz creates temporal patterns
            </p>
          </div>
          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-3 rounded-lg">
            <p className="text-sm font-medium text-zinc-900 dark:text-white">E-Ink Displays</p>
            <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">
              Moderate detection - different grid structure
            </p>
          </div>
        </div>
      </div>

      {/* Limitations */}
      <div className="bg-yellow-50 dark:bg-yellow-900/20 border-l-4 border-yellow-500 p-4 rounded-r-lg">
        <h3 className="font-semibold text-yellow-800 dark:text-yellow-300 mb-2">
          Limitations
        </h3>
        <ul className="text-sm text-yellow-700 dark:text-yellow-400 space-y-2">
          <li>
            <strong>Chimera-Style Attacks:</strong> Sophisticated adversaries can craft images
            that minimize Moire patterns while still being screen captures. This is why
            Moire is a SUPPORTING signal, not PRIMARY.
          </li>
          <li>
            <strong>Printed Photos:</strong> Moire detection is less effective for detecting
            photographs of printed images, which use halftone patterns instead.
          </li>
          <li>
            <strong>Anti-Aliasing:</strong> Some screens use anti-aliasing techniques that
            reduce detectable patterns.
          </li>
        </ul>
      </div>

      {/* Weight in confidence */}
      <div className="flex items-center justify-between p-3 bg-zinc-100 dark:bg-zinc-800 rounded-lg">
        <span className="text-sm text-zinc-600 dark:text-zinc-400">Weight in Confidence Calculation</span>
        <span className="text-sm font-semibold text-zinc-900 dark:text-white">15%</span>
      </div>
    </div>
  );
}
