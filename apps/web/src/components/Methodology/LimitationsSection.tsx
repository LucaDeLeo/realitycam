/**
 * LimitationsSection - Explains known limitations and threat model
 *
 * Content from PRD threat model section: What can and cannot be detected,
 * threat model assumptions, and Chimera attack mitigation.
 */

/** What can be detected */
const CAN_DETECT = [
  {
    threat: 'Screenshots and Photos of Screens',
    description: 'LiDAR depth analysis detects the flat screen surface. Moire and texture analysis provide supporting evidence.',
    confidence: 'Very High',
  },
  {
    threat: 'Photos of Printed Images',
    description: 'Halftone detection and texture classification identify printed materials. LiDAR sees flat paper surface.',
    confidence: 'High',
  },
  {
    threat: 'Device Compromise (Jailbreak/Root)',
    description: 'Hardware attestation detects modified operating systems and compromised boot chains.',
    confidence: 'Very High',
  },
  {
    threat: 'Timestamp Manipulation',
    description: 'Cryptographic binding ties captures to specific moments. Server validates timestamp against attestation.',
    confidence: 'High',
  },
  {
    threat: 'App Tampering',
    description: 'DCAppAttest/Key Attestation verify the rial. app binary has not been modified.',
    confidence: 'Very High',
  },
  {
    threat: 'Basic Photo Editing',
    description: 'Post-capture modifications break the cryptographic chain of custody. Hash verification fails.',
    confidence: 'Very High',
  },
];

/** What cannot be detected */
const CANNOT_DETECT = [
  {
    threat: 'Perfectly Constructed 3D Physical Replicas',
    description: 'If someone builds a physical 3D scene (miniature set, mannequins, etc.), LiDAR will see real depth. This is inherently undetectable as it IS a real 3D scene.',
    mitigation: 'Semantic analysis could help, but physical replicas are expensive and time-consuming to create.',
  },
  {
    threat: 'Nation-State Hardware Attacks',
    description: 'Sophisticated adversaries with physical device access and hardware tools could potentially extract Secure Enclave keys or clone devices.',
    mitigation: 'These attacks require significant resources and expertise. Not practical for most scenarios.',
  },
  {
    threat: 'Semantic Truth (Staged Scenes)',
    description: 'We verify the capture is of a real scene, not that the scene itself is truthful. A staged protest or fake accident scene would pass verification.',
    mitigation: 'rial. verifies authenticity, not truth. Interpreting semantic content requires human judgment.',
  },
  {
    threat: 'Pre-Capture Manipulation',
    description: 'If content is altered before capture (e.g., Photoshopped image displayed on screen then photographed with rial.), we detect the screen, not the original manipulation.',
    mitigation: 'Detection methods identify screen captures, protecting against this specific attack vector.',
  },
  {
    threat: 'Advanced AI-Generated Content',
    description: 'Future AI systems may generate photorealistic 3D scenes with synthetic depth maps that pass all checks.',
    mitigation: 'Hardware attestation remains secure. Ongoing research into AI detection methods.',
  },
];

/** Threat model assumptions */
const ASSUMPTIONS = [
  {
    assumption: 'Secure Enclave/TEE Hardware is Trustworthy',
    explanation: 'We assume Apple\'s Secure Enclave and Google\'s StrongBox/TEE implementations are secure. If these are compromised at the hardware level, all bets are off.',
    risk: 'Low - These are thoroughly audited by security researchers.',
  },
  {
    assumption: 'App Binary Has Not Been Modified',
    explanation: 'Attestation verifies the app, but only at key generation time. Runtime attacks are possible but difficult.',
    risk: 'Medium - Covered by attestation but not perfect.',
  },
  {
    assumption: 'Network Communication is Secure',
    explanation: 'TLS/HTTPS protects data in transit. Certificate pinning prevents MITM attacks.',
    risk: 'Low - Standard security practices.',
  },
  {
    assumption: 'Server Infrastructure is Secure',
    explanation: 'Backend security is critical. Compromised servers could issue fraudulent attestations.',
    risk: 'Medium - Requires ongoing security monitoring.',
  },
];

/**
 * LimitationsSection - Main content component
 */
export function LimitationsSection() {
  return (
    <div className="space-y-6">
      {/* Honest statement */}
      <div className="bg-blue-50 dark:bg-blue-900/20 border-l-4 border-blue-500 p-4 rounded-r-lg">
        <p className="text-blue-900 dark:text-blue-100 font-medium">
          No verification system is perfect.
        </p>
        <p className="text-blue-800 dark:text-blue-200 text-sm mt-1">
          We believe in transparency about our capabilities and limitations. Understanding
          what we can and cannot detect helps you make informed decisions about verification results.
        </p>
      </div>

      {/* What we CAN detect */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3 flex items-center gap-2">
          <span className="w-5 h-5 rounded-full bg-green-500 flex items-center justify-center" aria-hidden="true">
            <svg className="w-3 h-3 text-white" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
            </svg>
          </span>
          What We CAN Detect
        </h3>
        <div className="space-y-3">
          {CAN_DETECT.map((item) => (
            <div
              key={item.threat}
              className="border border-green-200 dark:border-green-800 rounded-lg p-3 bg-green-50/50 dark:bg-green-900/10"
            >
              <div className="flex items-start justify-between gap-4">
                <div>
                  <h4 className="font-medium text-zinc-900 dark:text-white">{item.threat}</h4>
                  <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">{item.description}</p>
                </div>
                <span className="flex-shrink-0 text-xs px-2 py-0.5 rounded-full bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-300">
                  {item.confidence}
                </span>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* What we CANNOT detect */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3 flex items-center gap-2">
          <span className="w-5 h-5 rounded-full bg-red-500 flex items-center justify-center" aria-hidden="true">
            <svg className="w-3 h-3 text-white" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" />
            </svg>
          </span>
          What We CANNOT Detect
        </h3>
        <div className="space-y-3">
          {CANNOT_DETECT.map((item) => (
            <div
              key={item.threat}
              className="border border-red-200 dark:border-red-800 rounded-lg p-3 bg-red-50/50 dark:bg-red-900/10"
            >
              <h4 className="font-medium text-zinc-900 dark:text-white">{item.threat}</h4>
              <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">{item.description}</p>
              <p className="text-xs text-zinc-500 dark:text-zinc-500 mt-2">
                <strong className="text-zinc-700 dark:text-zinc-300">Mitigation: </strong>
                {item.mitigation}
              </p>
            </div>
          ))}
        </div>
      </div>

      {/* Threat model assumptions */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          Threat Model Assumptions
        </h3>
        <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-3">
          Our security model relies on the following assumptions. If these are violated,
          verification guarantees may be weakened.
        </p>
        <div className="space-y-3">
          {ASSUMPTIONS.map((item) => (
            <div
              key={item.assumption}
              className="border border-zinc-200 dark:border-zinc-700 rounded-lg p-3"
            >
              <div className="flex items-start justify-between gap-4">
                <div>
                  <h4 className="font-medium text-zinc-900 dark:text-white">{item.assumption}</h4>
                  <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">{item.explanation}</p>
                </div>
                <span className={`flex-shrink-0 text-xs px-2 py-0.5 rounded-full ${
                  item.risk.startsWith('Low')
                    ? 'bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-300'
                    : 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/50 dark:text-yellow-300'
                }`}>
                  {item.risk.split(' - ')[0]} risk
                </span>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Chimera attack note */}
      <div className="bg-yellow-50 dark:bg-yellow-900/20 border-l-4 border-yellow-500 p-4 rounded-r-lg">
        <h3 className="font-semibold text-yellow-800 dark:text-yellow-300 mb-2">
          Note on Chimera Attack
        </h3>
        <p className="text-sm text-yellow-700 dark:text-yellow-400 mb-2">
          The{' '}
          <a
            href="https://www.usenix.org/conference/usenixsecurity25"
            target="_blank"
            rel="noopener noreferrer"
            className="underline hover:no-underline"
          >
            Chimera attack (USENIX Security 2025)
          </a>
          {' '}demonstrates that AI-based detection methods (Moire, texture, etc.) can be
          bypassed by sophisticated adversaries who craft images to evade detection.
        </p>
        <p className="text-sm text-yellow-700 dark:text-yellow-400">
          <strong>Our mitigation:</strong> We use an attestation-first trust model where
          hardware attestation is the PRIMARY signal. Detection algorithms are SUPPORTING
          evidence only. This architecture ensures that even if detection is bypassed,
          the hardware attestation requirement remains intact.
        </p>
      </div>
    </div>
  );
}
