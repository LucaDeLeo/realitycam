/**
 * PlatformSection - Explains platform-specific attestation
 *
 * Content covering iOS Secure Enclave, Android StrongBox/TEE,
 * and what "unverified" means.
 */

/** Platform configurations */
const PLATFORMS = [
  {
    id: 'ios_secure_enclave',
    platform: 'iOS',
    level: 'Secure Enclave',
    trustLevel: 'Highest',
    color: 'green',
    description: 'Hardware security processor on iPhone Pro devices',
    features: [
      'Dedicated security chip isolated from main processor',
      'Keys generated and stored in hardware, never exported',
      'DCAppAttest API provides cryptographic proof of device identity',
      'Protected against jailbreak and OS-level attacks',
    ],
    howItWorks: [
      'On first launch, rial. generates a unique key pair in Secure Enclave',
      'Apple\'s attestation service verifies the device and app are genuine',
      'Each capture is signed with the device\'s private key',
      'Backend verifies signature using the registered public key',
    ],
    devices: 'All iPhone Pro models (12 Pro through 17 Pro)',
  },
  {
    id: 'android_strongbox',
    platform: 'Android',
    level: 'StrongBox',
    trustLevel: 'Highest',
    color: 'green',
    description: 'Hardware Security Module (HSM) on supported Android devices',
    features: [
      'Dedicated secure hardware similar to iOS Secure Enclave',
      'Tamper-resistant key storage',
      'Google\'s Key Attestation verifies device and app integrity',
      'Protected against rooting and bootloader unlocking',
    ],
    howItWorks: [
      'Key pair generated in StrongBox HSM',
      'Google\'s attestation service provides certificate chain',
      'Certificate includes device model, patch level, and boot state',
      'Backend validates full certificate chain to Google root',
    ],
    devices: 'Pixel 3+, Samsung S20+, and other flagship devices',
  },
  {
    id: 'android_tee',
    platform: 'Android',
    level: 'TEE (Trusted Execution Environment)',
    trustLevel: 'Medium',
    color: 'yellow',
    description: 'Software-isolated secure environment on most Android devices',
    features: [
      'Runs in isolated ARM TrustZone',
      'Better than software-only, but weaker than StrongBox',
      'Can be compromised by sophisticated OS-level attacks',
      'Widely available on mid-range and older devices',
    ],
    howItWorks: [
      'Similar to StrongBox but in isolated software environment',
      'Key attestation still validates device and app',
      'Certificate includes lower security level indicator',
      'Backend applies medium trust weighting',
    ],
    devices: 'Most Android devices from 2018 onwards',
  },
  {
    id: 'unverified',
    platform: 'Any',
    level: 'Unverified',
    trustLevel: 'None',
    color: 'red',
    description: 'Attestation failed or unavailable',
    features: [
      'Device could not prove its identity',
      'May indicate compromised device or network issues',
      'Captures still accepted but with reduced confidence',
      'Detection methods become primary signals',
    ],
    howItWorks: [
      'Attestation request failed or returned invalid response',
      'Could be network timeout, server issues, or device tampering',
      'Backend falls back to detection-only verification',
      'Maximum confidence capped at MEDIUM',
    ],
    devices: 'Any device where attestation fails',
  },
];

/**
 * PlatformSection - Main content component
 */
export function PlatformSection() {
  return (
    <div className="space-y-6">
      {/* Overview */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          What is Platform Attestation?
        </h3>
        <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed">
          Platform attestation proves that a capture came from a genuine, unmodified device
          running the authentic rial. app. This is the most reliable trust signal because
          it is backed by hardware security that cannot be spoofed through software.
        </p>
      </div>

      {/* Platform comparison table */}
      <div>
        <h3 className="text-base font-semibold text-zinc-900 dark:text-white mb-3">
          Trust Level Comparison
        </h3>
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-zinc-200 dark:border-zinc-700">
                <th className="text-left py-2 pr-4 font-medium text-zinc-900 dark:text-white">Platform</th>
                <th className="text-left py-2 pr-4 font-medium text-zinc-900 dark:text-white">Attestation Level</th>
                <th className="text-left py-2 pr-4 font-medium text-zinc-900 dark:text-white">Trust</th>
                <th className="text-left py-2 font-medium text-zinc-900 dark:text-white">Max Confidence</th>
              </tr>
            </thead>
            <tbody>
              <tr className="border-b border-zinc-100 dark:border-zinc-800">
                <td className="py-2 pr-4 text-zinc-700 dark:text-zinc-300">iOS Pro</td>
                <td className="py-2 pr-4 text-zinc-700 dark:text-zinc-300">Secure Enclave</td>
                <td className="py-2 pr-4">
                  <span className="text-xs px-2 py-0.5 rounded-full bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-300">
                    Highest
                  </span>
                </td>
                <td className="py-2 text-zinc-700 dark:text-zinc-300">VERY HIGH (95%+)</td>
              </tr>
              <tr className="border-b border-zinc-100 dark:border-zinc-800">
                <td className="py-2 pr-4 text-zinc-700 dark:text-zinc-300">Android (StrongBox)</td>
                <td className="py-2 pr-4 text-zinc-700 dark:text-zinc-300">StrongBox HSM</td>
                <td className="py-2 pr-4">
                  <span className="text-xs px-2 py-0.5 rounded-full bg-green-100 text-green-800 dark:bg-green-900/50 dark:text-green-300">
                    Highest
                  </span>
                </td>
                <td className="py-2 text-zinc-700 dark:text-zinc-300">HIGH (90%+)</td>
              </tr>
              <tr className="border-b border-zinc-100 dark:border-zinc-800">
                <td className="py-2 pr-4 text-zinc-700 dark:text-zinc-300">Android (TEE)</td>
                <td className="py-2 pr-4 text-zinc-700 dark:text-zinc-300">TrustZone TEE</td>
                <td className="py-2 pr-4">
                  <span className="text-xs px-2 py-0.5 rounded-full bg-yellow-100 text-yellow-800 dark:bg-yellow-900/50 dark:text-yellow-300">
                    Medium
                  </span>
                </td>
                <td className="py-2 text-zinc-700 dark:text-zinc-300">MEDIUM-HIGH (80%)</td>
              </tr>
              <tr className="border-b border-zinc-100 dark:border-zinc-800">
                <td className="py-2 pr-4 text-zinc-700 dark:text-zinc-300">Any (Failed)</td>
                <td className="py-2 pr-4 text-zinc-700 dark:text-zinc-300">Unverified</td>
                <td className="py-2 pr-4">
                  <span className="text-xs px-2 py-0.5 rounded-full bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-300">
                    None
                  </span>
                </td>
                <td className="py-2 text-zinc-700 dark:text-zinc-300">MEDIUM max (60%)</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      {/* Detailed platform info */}
      {PLATFORMS.map((platform) => (
        <div
          key={platform.id}
          className={`border rounded-lg p-4 ${
            platform.color === 'green'
              ? 'border-green-300 dark:border-green-700 bg-green-50 dark:bg-green-900/20'
              : platform.color === 'yellow'
                ? 'border-yellow-300 dark:border-yellow-700 bg-yellow-50 dark:bg-yellow-900/20'
                : 'border-red-300 dark:border-red-700 bg-red-50 dark:bg-red-900/20'
          }`}
        >
          <div className="flex items-start justify-between gap-4 mb-3">
            <div>
              <div className="flex items-center gap-2">
                <h4 className={`font-semibold ${
                  platform.color === 'green'
                    ? 'text-green-800 dark:text-green-300'
                    : platform.color === 'yellow'
                      ? 'text-yellow-800 dark:text-yellow-300'
                      : 'text-red-800 dark:text-red-300'
                }`}>
                  {platform.platform} - {platform.level}
                </h4>
              </div>
              <p className={`text-sm mt-1 ${
                platform.color === 'green'
                  ? 'text-green-700 dark:text-green-400'
                  : platform.color === 'yellow'
                    ? 'text-yellow-700 dark:text-yellow-400'
                    : 'text-red-700 dark:text-red-400'
              }`}>
                {platform.description}
              </p>
            </div>
            <span className={`flex-shrink-0 text-xs px-2 py-1 rounded-full font-medium ${
              platform.color === 'green'
                ? 'bg-green-200 dark:bg-green-800 text-green-800 dark:text-green-200'
                : platform.color === 'yellow'
                  ? 'bg-yellow-200 dark:bg-yellow-800 text-yellow-800 dark:text-yellow-200'
                  : 'bg-red-200 dark:bg-red-800 text-red-800 dark:text-red-200'
            }`}>
              {platform.trustLevel} Trust
            </span>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
            <div>
              <h5 className={`text-sm font-medium mb-2 ${
                platform.color === 'green'
                  ? 'text-green-800 dark:text-green-300'
                  : platform.color === 'yellow'
                    ? 'text-yellow-800 dark:text-yellow-300'
                    : 'text-red-800 dark:text-red-300'
              }`}>
                Key Features
              </h5>
              <ul className={`text-xs space-y-1 ${
                platform.color === 'green'
                  ? 'text-green-700 dark:text-green-400'
                  : platform.color === 'yellow'
                    ? 'text-yellow-700 dark:text-yellow-400'
                    : 'text-red-700 dark:text-red-400'
              }`}>
                {platform.features.map((feature, i) => (
                  <li key={i}>- {feature}</li>
                ))}
              </ul>
            </div>
            <div>
              <h5 className={`text-sm font-medium mb-2 ${
                platform.color === 'green'
                  ? 'text-green-800 dark:text-green-300'
                  : platform.color === 'yellow'
                    ? 'text-yellow-800 dark:text-yellow-300'
                    : 'text-red-800 dark:text-red-300'
              }`}>
                How It Works
              </h5>
              <ol className={`text-xs space-y-1 ${
                platform.color === 'green'
                  ? 'text-green-700 dark:text-green-400'
                  : platform.color === 'yellow'
                    ? 'text-yellow-700 dark:text-yellow-400'
                    : 'text-red-700 dark:text-red-400'
              }`}>
                {platform.howItWorks.map((step, i) => (
                  <li key={i}>{i + 1}. {step}</li>
                ))}
              </ol>
            </div>
          </div>

          <p className={`text-xs mt-3 pt-3 border-t ${
            platform.color === 'green'
              ? 'border-green-200 dark:border-green-700 text-green-600 dark:text-green-500'
              : platform.color === 'yellow'
                ? 'border-yellow-200 dark:border-yellow-700 text-yellow-600 dark:text-yellow-500'
                : 'border-red-200 dark:border-red-700 text-red-600 dark:text-red-500'
          }`}>
            <strong>Supported devices:</strong> {platform.devices}
          </p>
        </div>
      ))}
    </div>
  );
}
