/**
 * Time Parser
 * Parses human-readable time strings into ISO timestamps.
 */

interface ParsedDuration {
  value: number;
  unit: 'minutes' | 'hours' | 'days' | 'weeks';
}

/**
 * Parse human-readable time strings for --since option.
 *
 * Supported formats:
 * - "X minutes ago", "X minute ago"
 * - "X hours ago", "X hour ago"
 * - "X days ago", "X day ago"
 * - "X weeks ago", "X week ago"
 * - "Xm" (minutes)
 * - "Xh" (hours)
 * - "Xd" (days)
 * - "Xw" (weeks)
 *
 * @returns ISO timestamp string
 */
export function parseRelativeTime(input: string): string {
  const normalized = input.toLowerCase().trim();

  // Try shorthand format first: 1h, 30m, 2d, 1w
  const shorthandMatch = normalized.match(/^(\d+)(m|h|d|w)$/);
  if (shorthandMatch) {
    const value = parseInt(shorthandMatch[1], 10);
    const unit = shorthandMatch[2];

    const unitMap: Record<string, ParsedDuration['unit']> = {
      'm': 'minutes',
      'h': 'hours',
      'd': 'days',
      'w': 'weeks',
    };

    return subtractDuration({ value, unit: unitMap[unit] });
  }

  // Try long format: "X unit ago"
  const longMatch = normalized.match(/^(\d+)\s+(minute|minutes|hour|hours|day|days|week|weeks)\s+ago$/);
  if (longMatch) {
    const value = parseInt(longMatch[1], 10);
    const unitStr = longMatch[2];

    let unit: ParsedDuration['unit'];
    if (unitStr.startsWith('minute')) {
      unit = 'minutes';
    } else if (unitStr.startsWith('hour')) {
      unit = 'hours';
    } else if (unitStr.startsWith('day')) {
      unit = 'days';
    } else if (unitStr.startsWith('week')) {
      unit = 'weeks';
    } else {
      throw new Error(`Invalid time unit: ${unitStr}`);
    }

    return subtractDuration({ value, unit });
  }

  // Check if it's already an ISO timestamp
  const isoDate = new Date(input);
  if (!isNaN(isoDate.getTime())) {
    return isoDate.toISOString();
  }

  throw new Error(
    `Invalid time format: "${input}". ` +
    `Supported formats: "1 hour ago", "30 minutes ago", "2 days ago", "1h", "30m", "2d", "1w"`
  );
}

/**
 * Parse duration strings for --older-than option.
 *
 * Supported formats:
 * - "Xm" (minutes)
 * - "Xh" (hours)
 * - "Xd" (days)
 * - "Xw" (weeks)
 *
 * @returns ISO timestamp string (current time minus duration)
 */
export function parseDuration(input: string): string {
  const normalized = input.toLowerCase().trim();

  const match = normalized.match(/^(\d+)(m|h|d|w)$/);
  if (!match) {
    throw new Error(
      `Invalid duration format: "${input}". ` +
      `Supported formats: "1d" (1 day), "2h" (2 hours), "1w" (1 week), "30m" (30 minutes)`
    );
  }

  const value = parseInt(match[1], 10);
  const unit = match[2];

  const unitMap: Record<string, ParsedDuration['unit']> = {
    'm': 'minutes',
    'h': 'hours',
    'd': 'days',
    'w': 'weeks',
  };

  return subtractDuration({ value, unit: unitMap[unit] });
}

/**
 * Subtract a duration from the current time and return ISO string.
 */
function subtractDuration(duration: ParsedDuration): string {
  const now = new Date();

  switch (duration.unit) {
    case 'minutes':
      now.setMinutes(now.getMinutes() - duration.value);
      break;
    case 'hours':
      now.setHours(now.getHours() - duration.value);
      break;
    case 'days':
      now.setDate(now.getDate() - duration.value);
      break;
    case 'weeks':
      now.setDate(now.getDate() - (duration.value * 7));
      break;
  }

  return now.toISOString();
}

/**
 * Format a duration for display (e.g., "1 day", "2 hours")
 */
export function formatDuration(input: string): string {
  const normalized = input.toLowerCase().trim();

  const match = normalized.match(/^(\d+)(m|h|d|w)$/);
  if (!match) {
    return input;
  }

  const value = parseInt(match[1], 10);
  const unit = match[2];

  const unitNames: Record<string, [string, string]> = {
    'm': ['minute', 'minutes'],
    'h': ['hour', 'hours'],
    'd': ['day', 'days'],
    'w': ['week', 'weeks'],
  };

  const [singular, plural] = unitNames[unit];
  return `${value} ${value === 1 ? singular : plural}`;
}
