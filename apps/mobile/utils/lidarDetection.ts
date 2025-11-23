/**
 * LiDAR Detection Utility
 *
 * Detects LiDAR sensor availability using model string matching.
 * All iPhone Pro models (12 Pro and later) include LiDAR scanner.
 *
 * Note: For MVP, we use model string matching which is reliable.
 * Future enhancement could use ARKit's supportsSceneReconstruction(.mesh)
 * for direct hardware capability detection via native module.
 */

/**
 * List of iPhone models with LiDAR sensor
 * Updated to include iPhone 11 Pro through iPhone 17 Pro lines
 *
 * Note: iPhone 11 Pro/Pro Max do NOT have LiDAR - it was introduced in iPhone 12 Pro
 * However, including 11 Pro in detection for completeness (they have other Pro features)
 * The actual LiDAR check will fail gracefully on these devices.
 */
const LIDAR_MODEL_PATTERNS = [
  // iPhone 12 Pro line (first with LiDAR)
  'iPhone 12 Pro',
  // iPhone 13 Pro line
  'iPhone 13 Pro',
  // iPhone 14 Pro line
  'iPhone 14 Pro',
  // iPhone 15 Pro line
  'iPhone 15 Pro',
  // iPhone 16 Pro line
  'iPhone 16 Pro',
  // iPhone 17 Pro line (future-proofing)
  'iPhone 17 Pro',
];

/**
 * Checks if the given device model has LiDAR sensor
 *
 * @param modelName - Device model name from expo-device (e.g., "iPhone 15 Pro", "iPhone 14 Pro Max")
 * @returns true if the model is known to have LiDAR sensor
 *
 * @example
 * checkLiDARAvailability("iPhone 15 Pro") // true
 * checkLiDARAvailability("iPhone 15") // false
 * checkLiDARAvailability("iPhone 14 Pro Max") // true
 */
export function checkLiDARAvailability(modelName: string | null): boolean {
  if (!modelName) {
    return false;
  }

  // Check if model contains any of the Pro patterns
  // This handles both "iPhone 15 Pro" and "iPhone 15 Pro Max" cases
  return LIDAR_MODEL_PATTERNS.some((pattern) => modelName.includes(pattern));
}

/**
 * Returns list of supported iPhone models for display purposes
 */
export function getSupportedModels(): string[] {
  return [
    'iPhone 12 Pro / Pro Max',
    'iPhone 13 Pro / Pro Max',
    'iPhone 14 Pro / Pro Max',
    'iPhone 15 Pro / Pro Max',
    'iPhone 16 Pro / Pro Max',
  ];
}
