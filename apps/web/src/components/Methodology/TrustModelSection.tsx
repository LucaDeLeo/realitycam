/**
 * TrustModelSection - Explains the attestation-first trust model
 *
 * Content from PRD lines 316-327: Trust hierarchy with hardware attestation
 * as PRIMARY, physical signals as STRONG SUPPORTING, and detection algorithms
 * as SUPPORTING (vulnerable to adversarial attack like Chimera).
 */

/** Trust hierarchy level configuration */
const TRUST_LEVELS = [
  {
    level: 1,
    name: 'Hardware Attestation',
    description: 'Secure Enclave (iOS) / StrongBox (Android)',
    examples: ['Device identity verified by Apple/Google', 'Private key never leaves secure hardware', 'App integrity validated'],
    color: 'bg-green-100 dark:bg-green-900/30 border-green-500',
    textColor: 'text-green-800 dark:text-green-300',
    trust: 'PRIMARY - Highest Trust',
  },
  {
    level: 2,
    name: 'Physical Depth Signals',
    description: 'LiDAR (iOS Pro) / Multi-Camera Parallax (Android)',
    examples: ['Direct 3D measurement of scene', 'Cannot be spoofed by 2D displays', 'Requires physical depth in scene'],
    color: 'bg-blue-100 dark:bg-blue-900/30 border-blue-500',
    textColor: 'text-blue-800 dark:text-blue-300',
    trust: 'STRONG - Supporting',
  },
  {
    level: 3,
    name: 'Detection Algorithms',
    description: 'Moire / Texture / Artifact Detection',
    examples: ['AI-based pattern recognition', 'Screen and print detection', 'Vulnerable to adversarial bypass'],
    color: 'bg-yellow-100 dark:bg-yellow-900/30 border-yellow-500',
    textColor: 'text-yellow-800 dark:text-yellow-300',
    trust: 'SUPPORTING - Vulnerable',
  },
];

/**
 * TrustHierarchyDiagram - Visual representation of trust levels
 */
function TrustHierarchyDiagram() {
  return (
    <div className="space-y-3" role="list" aria-label="Trust hierarchy levels">
      {TRUST_LEVELS.map((level, index) => (
        <div
          key={level.level}
          className={`relative rounded-lg border-l-4 p-4 ${level.color}`}
          role="listitem"
        >
          {/* Connector line */}
          {index < TRUST_LEVELS.length - 1 && (
            <div
              className="absolute left-6 -bottom-3 w-0.5 h-3 bg-zinc-300 dark:bg-zinc-600"
              aria-hidden="true"
            />
          )}

          <div className="flex items-start justify-between gap-4">
            <div>
              <div className="flex items-center gap-2 mb-1">
                <span className={`text-sm font-bold ${level.textColor}`}>
                  Level {level.level}
                </span>
                <span className={`text-xs px-2 py-0.5 rounded-full ${level.color} ${level.textColor}`}>
                  {level.trust}
                </span>
              </div>
              <h4 className="font-semibold text-zinc-900 dark:text-white">
                {level.name}
              </h4>
              <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">
                {level.description}
              </p>
              <ul className="mt-2 space-y-1">
                {level.examples.map((example, i) => (
                  <li key={i} className="text-sm text-zinc-500 dark:text-zinc-400 flex items-start gap-2">
                    <span className="text-zinc-400 dark:text-zinc-500" aria-hidden="true">-</span>
                    {example}
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

/**
 * TrustModelSection - Main content component
 */
export function TrustModelSection() {
  return (
    <div className="space-y-6">
      {/* Core principle */}
      <div className="bg-blue-50 dark:bg-blue-900/20 border-l-4 border-blue-500 p-4 rounded-r-lg">
        <p className="text-blue-900 dark:text-blue-100 font-medium">
          Hardware attestation is the PRIMARY trust signal.
        </p>
        <p className="text-blue-800 dark:text-blue-200 text-sm mt-1">
          Detection algorithms provide supporting evidence but are vulnerable to adversarial bypass.
          A capture with strong hardware attestation and weak detection signals is MORE trustworthy
          than strong detection with weak attestation.
        </p>
      </div>

      {/* Trust hierarchy diagram */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-4">
          Trust Hierarchy
        </h3>
        <TrustHierarchyDiagram />
      </div>

      {/* Why this matters */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          Why This Ordering Matters
        </h3>
        <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed">
          Research, including the{' '}
          <a
            href="https://www.usenix.org/conference/usenixsecurity25"
            target="_blank"
            rel="noopener noreferrer"
            className="text-blue-600 dark:text-blue-400 underline hover:no-underline"
          >
            Chimera attack (USENIX Security 2025)
          </a>
          , demonstrates that AI-based detection algorithms can be fooled by sophisticated
          adversaries. An attacker can craft images that pass Moire detection, texture classification,
          and artifact detection while still being photographs of screens.
        </p>
        <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed mt-3">
          Hardware attestation from the Secure Enclave or TEE/StrongBox cannot be bypassed without
          physical access to the device and sophisticated hardware attacks. This makes it the
          only reliable root of trust for media authenticity.
        </p>
      </div>

      {/* What attestation proves */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          What &quot;Attestation&quot; Proves
        </h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-4 rounded-lg">
            <h4 className="font-medium text-zinc-900 dark:text-white mb-2">Device Identity</h4>
            <p className="text-sm text-zinc-600 dark:text-zinc-400">
              The capture came from a genuine Apple/Google device, not an emulator or modified device.
            </p>
          </div>
          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-4 rounded-lg">
            <h4 className="font-medium text-zinc-900 dark:text-white mb-2">App Integrity</h4>
            <p className="text-sm text-zinc-600 dark:text-zinc-400">
              The rial. app was not modified or tampered with when the capture was taken.
            </p>
          </div>
          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-4 rounded-lg">
            <h4 className="font-medium text-zinc-900 dark:text-white mb-2">Key Protection</h4>
            <p className="text-sm text-zinc-600 dark:text-zinc-400">
              Signing keys are stored in secure hardware and cannot be extracted or copied.
            </p>
          </div>
          <div className="bg-zinc-50 dark:bg-zinc-800/50 p-4 rounded-lg">
            <h4 className="font-medium text-zinc-900 dark:text-white mb-2">Capture Binding</h4>
            <p className="text-sm text-zinc-600 dark:text-zinc-400">
              Each capture is cryptographically bound to the moment it was taken on that device.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
