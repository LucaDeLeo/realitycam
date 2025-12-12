/**
 * ConfidenceSection - Explains confidence calculation methodology
 *
 * Content from PRD lines 358-375: Confidence weighting for iOS Pro
 * and Android, plus confidence level thresholds.
 */

/** iOS Pro weights */
const IOS_PRO_WEIGHTS = [
  { method: 'LiDAR Depth', weight: 0.55, description: 'Most reliable physical signal - direct 3D measurement' },
  { method: 'Moire Detection', weight: 0.15, description: 'Reduced weight due to Chimera vulnerability' },
  { method: 'Texture Classification', weight: 0.15, description: 'ML-based material analysis' },
  { method: 'Supporting Signals', weight: 0.15, description: 'PWM, specular, halftone combined' },
];

/** Android weights */
const ANDROID_WEIGHTS = [
  { method: 'Attestation Level', weight: 0.20, description: 'StrongBox > TEE > Software' },
  { method: 'Multi-Camera Parallax', weight: 0.30, description: 'Primary depth signal (replaces LiDAR)' },
  { method: 'Moire Detection', weight: 0.15, description: 'Reduced weight due to Chimera vulnerability' },
  { method: 'Texture Classification', weight: 0.20, description: 'Higher weight without LiDAR' },
  { method: 'Supporting Signals', weight: 0.15, description: 'PWM, specular, halftone combined' },
];

/** Confidence level thresholds */
const CONFIDENCE_LEVELS = [
  {
    level: 'HIGH',
    range: '85%+',
    requirements: 'Score >= 85% AND attestation passed',
    meaning: 'Strong confidence in authenticity. Hardware attestation verified, primary signal passed, supporting signals agree.',
    color: 'green',
  },
  {
    level: 'MEDIUM',
    range: '60-85%',
    requirements: 'Score 60-85% OR attestation issues',
    meaning: 'Moderate confidence. Some checks may have warnings or reduced certainty. Review supporting evidence.',
    color: 'yellow',
  },
  {
    level: 'LOW',
    range: 'Below 60%',
    requirements: 'Score < 60%',
    meaning: 'Low confidence. Multiple checks failed or produced weak results. Proceed with caution.',
    color: 'orange',
  },
  {
    level: 'SUSPICIOUS',
    range: 'Any (with FAIL)',
    requirements: 'Any primary check explicitly FAIL',
    meaning: 'One or more checks detected likely manipulation. Evidence suggests the capture is not authentic.',
    color: 'red',
  },
];

/**
 * WeightsTable - Displays method weights
 */
function WeightsTable({ weights, title }: { weights: typeof IOS_PRO_WEIGHTS; title: string }) {
  return (
    <div className="bg-zinc-50 dark:bg-zinc-800/50 rounded-lg p-4">
      <h4 className="font-medium text-zinc-900 dark:text-white mb-3">{title}</h4>
      <div className="space-y-2">
        {weights.map((item) => (
          <div key={item.method} className="flex items-center gap-3">
            <div className="flex-1">
              <div className="flex items-center justify-between mb-1">
                <span className="text-sm font-medium text-zinc-700 dark:text-zinc-300">{item.method}</span>
                <span className="text-sm font-semibold text-zinc-900 dark:text-white">{(item.weight * 100).toFixed(0)}%</span>
              </div>
              <div className="h-2 bg-zinc-200 dark:bg-zinc-700 rounded-full overflow-hidden">
                <div
                  className="h-full bg-blue-500 dark:bg-blue-400 rounded-full"
                  style={{ width: `${item.weight * 100}%` }}
                />
              </div>
              <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">{item.description}</p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

/**
 * ConfidenceSection - Main content component
 */
export function ConfidenceSection() {
  return (
    <div className="space-y-6">
      {/* Overview */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          How Confidence is Calculated
        </h3>
        <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed">
          The overall confidence score is a weighted average of individual method scores,
          with weights reflecting each method&apos;s reliability. Different platforms use
          different weights based on available sensors and attestation capabilities.
        </p>
      </div>

      {/* Formula */}
      <div className="bg-zinc-100 dark:bg-zinc-800 p-4 rounded-lg font-mono text-sm">
        <p className="text-zinc-700 dark:text-zinc-300 mb-2">Confidence = Sum of (Method Score * Method Weight)</p>
        <p className="text-zinc-500 dark:text-zinc-400 text-xs">
          Example: (LiDAR: 0.95 * 0.55) + (Moire: 0.0 * 0.15) + (Texture: 0.88 * 0.15) + (Supporting: 0.79 * 0.15) = 0.77
        </p>
      </div>

      {/* Platform weights */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          Method Weights by Platform
        </h3>
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <WeightsTable weights={IOS_PRO_WEIGHTS} title="iOS Pro (LiDAR)" />
          <WeightsTable weights={ANDROID_WEIGHTS} title="Android" />
        </div>
      </div>

      {/* Why weights differ */}
      <div className="bg-blue-50 dark:bg-blue-900/20 border-l-4 border-blue-500 p-4 rounded-r-lg">
        <h3 className="font-semibold text-blue-800 dark:text-blue-300 mb-2">
          Why Weights Differ
        </h3>
        <ul className="text-sm text-blue-700 dark:text-blue-400 space-y-2">
          <li>
            <strong>LiDAR is heavily weighted (55%)</strong> because it provides direct
            physical measurement that cannot be spoofed by screens or prints.
          </li>
          <li>
            <strong>Moire is reduced (15%)</strong> because research shows it can be
            bypassed by sophisticated adversaries (Chimera attack).
          </li>
          <li>
            <strong>Android adds attestation weight (20%)</strong> because without LiDAR,
            attestation level becomes more important for trust.
          </li>
        </ul>
      </div>

      {/* Confidence levels */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          Confidence Level Thresholds
        </h3>
        <div className="space-y-3">
          {CONFIDENCE_LEVELS.map((level) => (
            <div
              key={level.level}
              className={`border rounded-lg p-4 ${
                level.color === 'green'
                  ? 'border-green-300 dark:border-green-700 bg-green-50 dark:bg-green-900/20'
                  : level.color === 'yellow'
                    ? 'border-yellow-300 dark:border-yellow-700 bg-yellow-50 dark:bg-yellow-900/20'
                    : level.color === 'orange'
                      ? 'border-orange-300 dark:border-orange-700 bg-orange-50 dark:bg-orange-900/20'
                      : 'border-red-300 dark:border-red-700 bg-red-50 dark:bg-red-900/20'
              }`}
            >
              <div className="flex items-start justify-between gap-4">
                <div>
                  <div className="flex items-center gap-2 mb-1">
                    <span className={`font-bold ${
                      level.color === 'green'
                        ? 'text-green-800 dark:text-green-300'
                        : level.color === 'yellow'
                          ? 'text-yellow-800 dark:text-yellow-300'
                          : level.color === 'orange'
                            ? 'text-orange-800 dark:text-orange-300'
                            : 'text-red-800 dark:text-red-300'
                    }`}>
                      {level.level}
                    </span>
                    <span className="text-sm text-zinc-500 dark:text-zinc-400">({level.range})</span>
                  </div>
                  <p className="text-xs text-zinc-600 dark:text-zinc-400 mb-2">
                    <strong>Requirements:</strong> {level.requirements}
                  </p>
                  <p className={`text-sm ${
                    level.color === 'green'
                      ? 'text-green-700 dark:text-green-400'
                      : level.color === 'yellow'
                        ? 'text-yellow-700 dark:text-yellow-400'
                        : level.color === 'orange'
                          ? 'text-orange-700 dark:text-orange-400'
                          : 'text-red-700 dark:text-red-400'
                  }`}>
                    {level.meaning}
                  </p>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Cross-validation impact */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          Cross-Validation Impact
        </h3>
        <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed">
          After calculating the weighted average, cross-validation penalties are applied:
        </p>
        <div className="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div className="bg-green-50 dark:bg-green-900/20 p-3 rounded-lg">
            <p className="text-sm font-medium text-green-800 dark:text-green-300">Agreement Bonus</p>
            <p className="text-xs text-green-700 dark:text-green-400 mt-1">
              +5% when all methods agree as expected
            </p>
          </div>
          <div className="bg-red-50 dark:bg-red-900/20 p-3 rounded-lg">
            <p className="text-sm font-medium text-red-800 dark:text-red-300">Disagreement Penalty</p>
            <p className="text-xs text-red-700 dark:text-red-400 mt-1">
              -5% to -25% depending on anomaly severity
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
