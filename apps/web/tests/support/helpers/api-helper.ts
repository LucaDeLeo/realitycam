/**
 * API Helper - Pure Functions
 *
 * Framework-agnostic HTTP helpers for test setup and verification.
 * These can be used in Playwright fixtures or standalone scripts.
 *
 * @see fixture-architecture.md - "Pure Function → Fixture Pattern"
 */

export interface ApiResponse<T = unknown> {
  data: T;
  status: number;
  ok: boolean;
}

export interface RequestOptions {
  headers?: Record<string, string>;
  timeout?: number;
}

const DEFAULT_TIMEOUT = 30000;

/**
 * Make HTTP GET request
 */
export async function apiGet<T>(baseUrl: string, endpoint: string, options: RequestOptions = {}): Promise<ApiResponse<T>> {
  const url = `${baseUrl}${endpoint}`;
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), options.timeout || DEFAULT_TIMEOUT);

  try {
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        ...options.headers,
      },
      signal: controller.signal,
    });

    const data = (await response.json()) as T;

    return {
      data,
      status: response.status,
      ok: response.ok,
    };
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * Make HTTP POST request
 */
export async function apiPost<T>(baseUrl: string, endpoint: string, body: unknown, options: RequestOptions = {}): Promise<ApiResponse<T>> {
  const url = `${baseUrl}${endpoint}`;
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), options.timeout || DEFAULT_TIMEOUT);

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...options.headers,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    const data = (await response.json()) as T;

    return {
      data,
      status: response.status,
      ok: response.ok,
    };
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * Make HTTP DELETE request
 */
export async function apiDelete(baseUrl: string, endpoint: string, options: RequestOptions = {}): Promise<ApiResponse<void>> {
  const url = `${baseUrl}${endpoint}`;
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), options.timeout || DEFAULT_TIMEOUT);

  try {
    const response = await fetch(url, {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
        ...options.headers,
      },
      signal: controller.signal,
    });

    return {
      data: undefined,
      status: response.status,
      ok: response.ok,
    };
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * Wait for API to become healthy
 */
export async function waitForApi(baseUrl: string, maxAttempts = 30, delayMs = 1000): Promise<boolean> {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const response = await apiGet(baseUrl, '/health', { timeout: 5000 });
      if (response.ok) {
        return true;
      }
    } catch {
      // API not ready yet
    }

    if (attempt < maxAttempts) {
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }

  return false;
}

/**
 * Seed test data via API
 */
export async function seedTestData<T>(baseUrl: string, endpoint: string, data: unknown[]): Promise<T[]> {
  const results: T[] = [];

  for (const item of data) {
    const response = await apiPost<T>(baseUrl, endpoint, item);
    if (!response.ok) {
      throw new Error(`Failed to seed data at ${endpoint}: ${response.status}`);
    }
    results.push(response.data);
  }

  return results;
}
