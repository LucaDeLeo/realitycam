/**
 * Status Utility Unit Tests
 *
 * [P1] Tests for status mapping and styling utility functions.
 * These are pure functions with no side effects - ideal for unit testing.
 *
 * @see src/lib/status.ts
 */

import { describe, test, expect } from 'vitest';
import {
  mapToEvidenceStatus,
  getStatusText,
  getVerificationBackground,
  getVerificationTitle,
  getConfidenceBadgeColor,
  getConfidenceFullColor,
  getConfidenceLabel,
} from '../status';
import type { ConfidenceLevel, EvidenceStatus } from '@realitycam/shared';

// ============================================================================
// mapToEvidenceStatus Tests
// ============================================================================

describe('mapToEvidenceStatus', () => {
  test('[P1] should map "pass" to "pass"', () => {
    // GIVEN: Current status name
    const status = 'pass';

    // WHEN: Mapping to evidence status
    const result = mapToEvidenceStatus(status);

    // THEN: Should return pass
    expect(result).toBe('pass');
  });

  test('[P1] should map legacy "verified" to "pass"', () => {
    // GIVEN: Legacy status name
    const status = 'verified';

    // WHEN: Mapping to evidence status
    const result = mapToEvidenceStatus(status);

    // THEN: Should return pass (handles legacy)
    expect(result).toBe('pass');
  });

  test('[P1] should map "fail" to "fail"', () => {
    // GIVEN: Current status name
    const status = 'fail';

    // WHEN: Mapping to evidence status
    const result = mapToEvidenceStatus(status);

    // THEN: Should return fail
    expect(result).toBe('fail');
  });

  test('[P1] should map legacy "failed" to "fail"', () => {
    // GIVEN: Legacy status name
    const status = 'failed';

    // WHEN: Mapping to evidence status
    const result = mapToEvidenceStatus(status);

    // THEN: Should return fail (handles legacy)
    expect(result).toBe('fail');
  });

  test('[P1] should map unknown status to "unavailable"', () => {
    // GIVEN: Unknown status values
    const unknownStatuses = ['unknown', 'pending', 'processing', 'xyz', ''];

    // WHEN/THEN: Each should map to unavailable
    unknownStatuses.forEach((status) => {
      expect(mapToEvidenceStatus(status)).toBe('unavailable');
    });
  });

  test('[P1] should handle undefined status', () => {
    // GIVEN: Undefined status
    const status = undefined;

    // WHEN: Mapping to evidence status
    const result = mapToEvidenceStatus(status);

    // THEN: Should return unavailable
    expect(result).toBe('unavailable');
  });
});

// ============================================================================
// getStatusText Tests
// ============================================================================

describe('getStatusText', () => {
  test('[P1] should return "Verified" for pass status', () => {
    expect(getStatusText('pass')).toBe('Verified');
  });

  test('[P1] should return "Failed" for fail status', () => {
    expect(getStatusText('fail')).toBe('Failed');
  });

  test('[P1] should return "Unavailable" for unavailable status', () => {
    expect(getStatusText('unavailable')).toBe('Unavailable');
  });

  test('[P1] should return "Pending" for pending status', () => {
    expect(getStatusText('pending')).toBe('Pending');
  });

  test('[P1] should return "Pending" for unknown status (default)', () => {
    // Type cast to test default case
    expect(getStatusText('unknown' as EvidenceStatus | 'pending')).toBe('Pending');
  });
});

// ============================================================================
// getVerificationBackground Tests
// ============================================================================

describe('getVerificationBackground', () => {
  test('[P1] should return green classes for verified status', () => {
    // GIVEN: Verified status
    const status = 'verified' as const;

    // WHEN: Getting background classes
    const result = getVerificationBackground(status);

    // THEN: Should contain green color classes
    expect(result).toContain('bg-green');
    expect(result).toContain('border-green');
  });

  test('[P1] should return yellow classes for c2pa_only status', () => {
    // GIVEN: C2PA only status
    const status = 'c2pa_only' as const;

    // WHEN: Getting background classes
    const result = getVerificationBackground(status);

    // THEN: Should contain yellow color classes
    expect(result).toContain('bg-yellow');
    expect(result).toContain('border-yellow');
  });

  test('[P1] should return zinc classes for no_record status', () => {
    // GIVEN: No record status
    const status = 'no_record' as const;

    // WHEN: Getting background classes
    const result = getVerificationBackground(status);

    // THEN: Should contain zinc/neutral color classes
    expect(result).toContain('bg-zinc');
    expect(result).toContain('border-zinc');
  });
});

// ============================================================================
// getVerificationTitle Tests
// ============================================================================

describe('getVerificationTitle', () => {
  test('[P1] should return correct title for verified status', () => {
    expect(getVerificationTitle('verified')).toBe('Photo Verified');
  });

  test('[P1] should return correct title for c2pa_only status', () => {
    expect(getVerificationTitle('c2pa_only')).toBe('Content Credentials Found');
  });

  test('[P1] should return correct title for no_record status', () => {
    expect(getVerificationTitle('no_record')).toBe('No Record Found');
  });
});

// ============================================================================
// getConfidenceBadgeColor Tests
// ============================================================================

describe('getConfidenceBadgeColor', () => {
  test('[P1] should return green classes for high confidence', () => {
    // GIVEN: High confidence level
    const level: ConfidenceLevel = 'high';

    // WHEN: Getting badge color
    const result = getConfidenceBadgeColor(level);

    // THEN: Should contain green color classes
    expect(result).toContain('bg-green');
    expect(result).toContain('text-green');
  });

  test('[P1] should return yellow classes for medium confidence', () => {
    const level: ConfidenceLevel = 'medium';
    const result = getConfidenceBadgeColor(level);

    expect(result).toContain('bg-yellow');
    expect(result).toContain('text-yellow');
  });

  test('[P1] should return orange classes for low confidence', () => {
    const level: ConfidenceLevel = 'low';
    const result = getConfidenceBadgeColor(level);

    expect(result).toContain('bg-orange');
    expect(result).toContain('text-orange');
  });

  test('[P1] should return red classes for suspicious confidence', () => {
    const level: ConfidenceLevel = 'suspicious';
    const result = getConfidenceBadgeColor(level);

    expect(result).toContain('bg-red');
    expect(result).toContain('text-red');
  });

  test('[P1] should return zinc classes for unknown confidence (default)', () => {
    // Type cast to test default case
    const level = 'unknown' as ConfidenceLevel;
    const result = getConfidenceBadgeColor(level);

    expect(result).toContain('bg-zinc');
    expect(result).toContain('text-zinc');
  });

  test('[P1] should include dark mode classes', () => {
    // GIVEN: Any confidence level
    const level: ConfidenceLevel = 'high';

    // WHEN: Getting badge color
    const result = getConfidenceBadgeColor(level);

    // THEN: Should include dark mode variants
    expect(result).toContain('dark:');
  });
});

// ============================================================================
// getConfidenceFullColor Tests
// ============================================================================

describe('getConfidenceFullColor', () => {
  test('[P1] should return full styling for high confidence', () => {
    const result = getConfidenceFullColor('high');

    // Should include text, background, and border colors
    expect(result).toContain('text-green');
    expect(result).toContain('bg-green');
    expect(result).toContain('border-green');
  });

  test('[P1] should return full styling for all confidence levels', () => {
    const levels: ConfidenceLevel[] = ['high', 'medium', 'low', 'suspicious'];

    levels.forEach((level) => {
      const result = getConfidenceFullColor(level);

      // Each should have text, bg, and border
      expect(result).toMatch(/text-/);
      expect(result).toMatch(/bg-/);
      expect(result).toMatch(/border-/);
      expect(result).toMatch(/dark:/);
    });
  });
});

// ============================================================================
// getConfidenceLabel Tests
// ============================================================================

describe('getConfidenceLabel', () => {
  test('[P1] should return uppercase labels for all confidence levels', () => {
    expect(getConfidenceLabel('high')).toBe('HIGH CONFIDENCE');
    expect(getConfidenceLabel('medium')).toBe('MEDIUM CONFIDENCE');
    expect(getConfidenceLabel('low')).toBe('LOW CONFIDENCE');
    expect(getConfidenceLabel('suspicious')).toBe('SUSPICIOUS');
  });

  test('[P1] should return "UNKNOWN" for unknown level', () => {
    const level = 'unknown' as ConfidenceLevel;
    expect(getConfidenceLabel(level)).toBe('UNKNOWN');
  });
});

// ============================================================================
// Edge Cases and Comprehensive Coverage
// ============================================================================

describe('Edge Cases', () => {
  test('[P2] all functions should be pure (no side effects)', () => {
    // GIVEN: Multiple calls with same input
    const level: ConfidenceLevel = 'high';

    // WHEN: Calling functions multiple times
    const results1 = [
      getConfidenceBadgeColor(level),
      getConfidenceFullColor(level),
      getConfidenceLabel(level),
    ];

    const results2 = [
      getConfidenceBadgeColor(level),
      getConfidenceFullColor(level),
      getConfidenceLabel(level),
    ];

    // THEN: Results should be identical (pure functions)
    expect(results1).toEqual(results2);
  });

  test('[P2] mapToEvidenceStatus handles all EvidenceStatus values', () => {
    // All valid EvidenceStatus values should round-trip correctly
    const statuses = ['pass', 'fail', 'unavailable'] as const;

    statuses.forEach((status) => {
      // When status equals the expected value, it should return it
      if (status === 'pass') {
        expect(mapToEvidenceStatus(status)).toBe('pass');
      } else if (status === 'fail') {
        expect(mapToEvidenceStatus(status)).toBe('fail');
      } else {
        // 'unavailable' maps to unavailable (but via default case)
        expect(mapToEvidenceStatus(status)).toBe('unavailable');
      }
    });
  });
});
