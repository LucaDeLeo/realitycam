/**
 * RealityCam iOS Color Constants
 * iOS Human Interface Guidelines compliant colors
 */

export const colors = {
  // iOS System Colors
  primary: '#007AFF', // iOS system blue
  systemGray: '#8E8E93', // iOS system gray

  // Tab Bar Colors
  tabBarActive: '#007AFF',
  tabBarInactive: '#8E8E93',

  // Background Colors
  background: '#FFFFFF',
  backgroundDark: '#000000',
  backgroundSecondary: '#F2F2F7', // iOS system gray 6

  // Text Colors
  text: '#000000',
  textDark: '#FFFFFF',
  textSecondary: '#6D6D72',

  // Border Colors
  border: '#C6C6C8',
  borderDark: '#38383A',

  // Warning Colors (for attestation failures)
  warning: '#FFF3CD', // Light mode warning background
  warningDark: '#664D03', // Dark mode warning background
  warningText: '#856404', // Light mode warning text
  warningTextDark: '#FFF3CD', // Dark mode warning text
} as const;

export type ColorKey = keyof typeof colors;
