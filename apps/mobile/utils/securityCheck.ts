/**
 * Security Check Utilities
 *
 * Shared functions for detecting security-related errors
 * such as jailbreak detection, device compromise, etc.
 */

/**
 * Security-related keywords to check for in error messages
 */
const SECURITY_ERROR_PATTERNS = [
  'jailbreak',
  'security',
  'tamper',
  'compromised',
  'restriction',
  'not supported',
  'device not supported',
] as const;

/**
 * Checks if an error indicates a security/compromise issue
 *
 * @param error - Error to check
 * @returns true if the error is security-related
 */
export function isSecurityError(error: Error): boolean {
  const message = error.message.toLowerCase();
  return SECURITY_ERROR_PATTERNS.some((pattern) => message.includes(pattern));
}
