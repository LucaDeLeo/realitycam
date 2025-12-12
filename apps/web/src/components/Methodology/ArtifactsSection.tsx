/**
 * ArtifactsSection - Explains artifact detection methodology
 *
 * Content from PRD lines 350-354: Supporting signals including
 * PWM/refresh rate artifacts, specular reflection patterns, halftone detection.
 */

/** Artifact types detected */
const ARTIFACT_TYPES = [
  {
    id: 'pwm_flicker',
    name: 'PWM Flicker',
    description: 'Pulse Width Modulation artifacts from screen backlight',
    howDetected: 'Analysis of brightness patterns that indicate backlight modulation, typically at 60-480Hz frequencies.',
    whenVisible: 'Most visible with LED/LCD backlights at low brightness settings.',
    icon: (
      <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M13 10V3L4 14h7v7l9-11h-7z" />
      </svg>
    ),
  },
  {
    id: 'specular_reflection',
    name: 'Specular Reflection',
    description: 'Unnatural reflection patterns from glossy screens',
    howDetected: 'Detection of uniform specular highlights that indicate flat, glossy surfaces like screens or glass.',
    whenVisible: 'When photographing screens at angles or in rooms with light sources.',
    icon: (
      <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" />
      </svg>
    ),
  },
  {
    id: 'halftone',
    name: 'Halftone Patterns',
    description: 'Dot patterns from printed material',
    howDetected: 'Frequency analysis detecting regular dot grids used in offset printing, inkjet, and laser printing.',
    whenVisible: 'When photographing newspapers, magazines, or printed photos.',
    icon: (
      <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6zM16 13a1 1 0 011-1h2a1 1 0 011 1v6a1 1 0 01-1 1h-2a1 1 0 01-1-1v-6z" />
      </svg>
    ),
  },
];

/**
 * ArtifactsSection - Main content component
 */
export function ArtifactsSection() {
  return (
    <div className="space-y-6">
      {/* What artifact detection does */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          What is Artifact Detection?
        </h3>
        <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed">
          Artifact detection looks for telltale signs that an image was captured from an
          artificial source (screen or print) rather than a real scene. These artifacts
          are often invisible to the human eye but can be detected through computational
          analysis.
        </p>
      </div>

      {/* Artifact types */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          Detected Artifact Types
        </h3>
        <div className="space-y-4">
          {ARTIFACT_TYPES.map((artifact) => (
            <div
              key={artifact.id}
              className="border border-zinc-200 dark:border-zinc-700 rounded-lg p-4 bg-white dark:bg-zinc-800/50"
            >
              <div className="flex items-start gap-4">
                <div className="flex-shrink-0 w-10 h-10 rounded-lg bg-zinc-100 dark:bg-zinc-700 flex items-center justify-center text-zinc-500 dark:text-zinc-400">
                  {artifact.icon}
                </div>
                <div className="flex-1">
                  <h4 className="font-semibold text-zinc-900 dark:text-white">
                    {artifact.name}
                  </h4>
                  <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">
                    {artifact.description}
                  </p>
                  <div className="mt-3 space-y-2 text-sm">
                    <p className="text-zinc-500 dark:text-zinc-500">
                      <span className="font-medium text-zinc-700 dark:text-zinc-300">How detected: </span>
                      {artifact.howDetected}
                    </p>
                    <p className="text-zinc-500 dark:text-zinc-500">
                      <span className="font-medium text-zinc-700 dark:text-zinc-300">When visible: </span>
                      {artifact.whenVisible}
                    </p>
                  </div>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Understanding the score */}
      <div className="bg-green-50 dark:bg-green-900/20 border-l-4 border-green-500 p-4 rounded-r-lg">
        <h3 className="font-semibold text-green-800 dark:text-green-300 mb-2">
          Understanding the Score
        </h3>
        <p className="text-sm text-green-700 dark:text-green-400 mb-3">
          For artifact detection, <strong>&quot;not detected&quot; is GOOD</strong>. This means:
        </p>
        <ul className="text-sm text-green-700 dark:text-green-400 space-y-1">
          <li>- No PWM flicker patterns found</li>
          <li>- No suspicious specular reflections</li>
          <li>- No halftone printing patterns</li>
          <li>- The image appears to be from a real scene</li>
        </ul>
      </div>

      {/* False positives */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          False Positive Scenarios
        </h3>
        <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-3">
          Some legitimate scenarios may trigger false positives:
        </p>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-3 rounded-lg">
            <p className="text-sm font-medium text-zinc-900 dark:text-white">LED Lighting</p>
            <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">
              Some LED lights use PWM dimming that can be detected in photos
            </p>
          </div>
          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-3 rounded-lg">
            <p className="text-sm font-medium text-zinc-900 dark:text-white">Glossy Surfaces</p>
            <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">
              Glass, water, or polished surfaces may create screen-like reflections
            </p>
          </div>
          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-3 rounded-lg">
            <p className="text-sm font-medium text-zinc-900 dark:text-white">Patterned Fabrics</p>
            <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">
              Regular weave patterns may resemble halftone patterns
            </p>
          </div>
          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-3 rounded-lg">
            <p className="text-sm font-medium text-zinc-900 dark:text-white">Window Screens</p>
            <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">
              Physical window mesh can create Moire-like interference
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
            <strong>High-Quality Displays:</strong> Premium OLED screens with DC dimming
            produce fewer detectable artifacts.
          </li>
          <li>
            <strong>Professional Prints:</strong> High-quality photographic prints use
            dye-sublimation or similar processes that do not produce halftone patterns.
          </li>
          <li>
            <strong>Controlled Lighting:</strong> Artifacts are most detectable under
            certain lighting conditions. Well-lit screen captures may have fewer artifacts.
          </li>
        </ul>
      </div>

      {/* Weight in confidence */}
      <div className="flex items-center justify-between p-3 bg-zinc-100 dark:bg-zinc-800 rounded-lg">
        <span className="text-sm text-zinc-600 dark:text-zinc-400">Weight in Confidence Calculation</span>
        <span className="text-sm font-semibold text-zinc-900 dark:text-white">15% (Supporting Signals)</span>
      </div>
    </div>
  );
}
