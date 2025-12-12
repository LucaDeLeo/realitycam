/**
 * CrossValidationMethodSection - Explains cross-validation methodology
 *
 * Content from PRD lines 378-384: Cross-validation when multiple detection
 * methods are available, including agreement/disagreement handling.
 */

/** Expected relationships between methods */
const METHOD_RELATIONSHIPS = [
  {
    methodA: 'LiDAR',
    methodB: 'Moire',
    relationship: 'Negative',
    explanation: 'If LiDAR shows real 3D depth, Moire should NOT detect screen patterns. If both pass, this is expected. If LiDAR passes but Moire detects a screen, something is wrong.',
    color: 'text-blue-600 dark:text-blue-400',
  },
  {
    methodA: 'LiDAR',
    methodB: 'Texture',
    relationship: 'Positive',
    explanation: 'If LiDAR shows real depth, texture should classify as "real_scene". Both should agree on authenticity.',
    color: 'text-green-600 dark:text-green-400',
  },
  {
    methodA: 'LiDAR',
    methodB: 'Artifacts',
    relationship: 'Positive',
    explanation: 'Real 3D scenes shouldn\'t have screen artifacts. If LiDAR passes, artifacts should not be detected.',
    color: 'text-green-600 dark:text-green-400',
  },
  {
    methodA: 'Moire',
    methodB: 'Texture',
    relationship: 'Neutral',
    explanation: 'These methods detect different things. Moire detects pixel patterns; texture analyzes material. They may not always agree.',
    color: 'text-zinc-600 dark:text-zinc-400',
  },
];

/** Anomaly types and their implications */
const ANOMALY_TYPES = [
  {
    type: 'Contradictory Signals',
    severity: 'high',
    description: 'Primary and supporting signals disagree on authenticity',
    implication: 'Potential tampering or sophisticated attack attempt',
    action: 'Confidence capped, flagged for review',
  },
  {
    type: 'Too Perfect Agreement',
    severity: 'medium',
    description: 'All signals agree with suspiciously high precision',
    implication: 'May indicate synthetic or manipulated evidence',
    action: 'Minor confidence penalty',
  },
  {
    type: 'Isolated Disagreement',
    severity: 'low',
    description: 'One supporting method disagrees while others agree',
    implication: 'Likely environmental factor or edge case',
    action: 'Noted but minimal penalty',
  },
  {
    type: 'Boundary Clustering',
    severity: 'medium',
    description: 'Multiple scores cluster around decision boundaries',
    implication: 'Uncertainty in classification, edge case scenario',
    action: 'Widened confidence interval',
  },
];

/**
 * CrossValidationMethodSection - Main content component
 */
export function CrossValidationMethodSection() {
  return (
    <div className="space-y-6">
      {/* Why cross-validation matters */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          Why Cross-Validation Matters
        </h3>
        <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed">
          Individual detection methods can be fooled or may fail in certain conditions.
          Cross-validation checks that multiple independent methods agree on the result.
          When methods that should agree (or disagree) do not behave as expected, this
          signals a potential problem.
        </p>
        <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed mt-3">
          Think of it like witness testimony - if multiple independent witnesses tell
          the same story, it is more believable. If they contradict each other, something
          is wrong.
        </p>
      </div>

      {/* Expected relationships */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          Expected Relationships Between Methods
        </h3>
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-zinc-200 dark:border-zinc-700">
                <th className="text-left py-2 pr-4 font-medium text-zinc-900 dark:text-white">Method A</th>
                <th className="text-left py-2 pr-4 font-medium text-zinc-900 dark:text-white">Method B</th>
                <th className="text-left py-2 pr-4 font-medium text-zinc-900 dark:text-white">Relationship</th>
                <th className="text-left py-2 font-medium text-zinc-900 dark:text-white">Explanation</th>
              </tr>
            </thead>
            <tbody>
              {METHOD_RELATIONSHIPS.map((rel, index) => (
                <tr key={index} className="border-b border-zinc-100 dark:border-zinc-800">
                  <td className="py-3 pr-4 text-zinc-700 dark:text-zinc-300">{rel.methodA}</td>
                  <td className="py-3 pr-4 text-zinc-700 dark:text-zinc-300">{rel.methodB}</td>
                  <td className={`py-3 pr-4 font-medium ${rel.color}`}>{rel.relationship}</td>
                  <td className="py-3 text-zinc-600 dark:text-zinc-400 text-xs max-w-xs">{rel.explanation}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Agreement vs Disagreement */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div className="border border-green-300 dark:border-green-700 rounded-lg p-4 bg-green-50 dark:bg-green-900/20">
          <div className="flex items-center gap-2 mb-2">
            <span className="w-3 h-3 rounded-full bg-green-500" aria-hidden="true" />
            <h4 className="font-semibold text-green-800 dark:text-green-300">Agreement</h4>
          </div>
          <p className="text-sm text-green-700 dark:text-green-400">
            Methods behave as expected based on their relationship type. This provides
            a confidence boost (+5%) because multiple independent signals support the
            same conclusion.
          </p>
        </div>
        <div className="border border-red-300 dark:border-red-700 rounded-lg p-4 bg-red-50 dark:bg-red-900/20">
          <div className="flex items-center gap-2 mb-2">
            <span className="w-3 h-3 rounded-full bg-red-500" aria-hidden="true" />
            <h4 className="font-semibold text-red-800 dark:text-red-300">Disagreement</h4>
          </div>
          <p className="text-sm text-red-700 dark:text-red-400">
            Methods contradict each other unexpectedly. This triggers anomaly detection
            and confidence penalties. The capture is flagged for review and confidence
            is capped at MEDIUM.
          </p>
        </div>
      </div>

      {/* Anomaly types */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          Anomaly Types
        </h3>
        <div className="space-y-3">
          {ANOMALY_TYPES.map((anomaly) => (
            <div
              key={anomaly.type}
              className="border border-zinc-200 dark:border-zinc-700 rounded-lg p-4"
            >
              <div className="flex items-start justify-between gap-4 mb-2">
                <h4 className="font-medium text-zinc-900 dark:text-white">{anomaly.type}</h4>
                <span className={`flex-shrink-0 text-xs px-2 py-0.5 rounded-full font-medium ${
                  anomaly.severity === 'high'
                    ? 'bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-300'
                    : anomaly.severity === 'medium'
                      ? 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/50 dark:text-yellow-300'
                      : 'bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400'
                }`}>
                  {anomaly.severity} severity
                </span>
              </div>
              <p className="text-sm text-zinc-600 dark:text-zinc-400">{anomaly.description}</p>
              <div className="mt-2 grid grid-cols-1 sm:grid-cols-2 gap-2 text-xs">
                <p className="text-zinc-500 dark:text-zinc-500">
                  <span className="font-medium text-zinc-700 dark:text-zinc-300">Implication: </span>
                  {anomaly.implication}
                </p>
                <p className="text-zinc-500 dark:text-zinc-500">
                  <span className="font-medium text-zinc-700 dark:text-zinc-300">Action: </span>
                  {anomaly.action}
                </p>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Confidence penalty calculation */}
      <div className="bg-zinc-50 dark:bg-zinc-800/50 p-4 rounded-lg">
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-2">
          Confidence Penalty Calculation
        </h3>
        <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-3">
          When anomalies are detected, penalties are applied to the overall confidence:
        </p>
        <ul className="text-sm text-zinc-600 dark:text-zinc-400 space-y-1">
          <li>- <span className="font-mono text-xs bg-zinc-200 dark:bg-zinc-700 px-1 rounded">High severity</span>: -15% to -25%</li>
          <li>- <span className="font-mono text-xs bg-zinc-200 dark:bg-zinc-700 px-1 rounded">Medium severity</span>: -5% to -15%</li>
          <li>- <span className="font-mono text-xs bg-zinc-200 dark:bg-zinc-700 px-1 rounded">Low severity</span>: -0% to -5%</li>
        </ul>
        <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-3">
          Multiple anomalies compound. Total penalty displayed in cross-validation results.
        </p>
      </div>

      {/* Temporal consistency (video) */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          Temporal Consistency (Video Only)
        </h3>
        <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed">
          For video captures, cross-validation also checks frame-by-frame stability.
          Detection results should remain consistent across frames - sudden jumps or
          inconsistencies between frames indicate potential manipulation.
        </p>
        <div className="mt-3 grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-3 rounded-lg">
            <p className="text-sm font-medium text-zinc-900 dark:text-white">Stability Score</p>
            <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">
              How consistent each method is across frames (0-1)
            </p>
          </div>
          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-3 rounded-lg">
            <p className="text-sm font-medium text-zinc-900 dark:text-white">Frame Anomalies</p>
            <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">
              Specific frames with unexpected result changes
            </p>
          </div>
          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-3 rounded-lg">
            <p className="text-sm font-medium text-zinc-900 dark:text-white">Overall Stability</p>
            <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">
              Combined stability across all methods
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
