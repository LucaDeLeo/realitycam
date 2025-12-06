/**
 * Debug CLI API Client
 * Communicates with the backend debug log endpoints.
 */

const DEFAULT_API_URL = 'http://localhost:8080';
const REQUEST_TIMEOUT_MS = 10_000;

export interface DebugLog {
  id: string;
  correlation_id: string;
  timestamp: string;
  source: 'ios' | 'backend' | 'web';
  level: 'debug' | 'info' | 'warn' | 'error';
  event: string;
  payload: Record<string, unknown>;
  device_id?: string;
  session_id?: string;
  created_at: string;
}

export interface QueryLogsResponse {
  logs: DebugLog[];
  count: number;
  has_more: boolean;
}

export interface DeleteResponse {
  deleted: number;
}

export interface LogStatsResponse {
  total_count: number;
  by_source: Record<string, number>;
  by_level: Record<string, number>;
  oldest_timestamp?: string;
  newest_timestamp?: string;
}

export interface QueryFilters {
  correlation_id?: string;
  source?: 'ios' | 'backend' | 'web';
  level?: 'debug' | 'info' | 'warn' | 'error';
  event?: string;
  since?: string; // ISO timestamp
  limit?: number;
  order?: 'asc' | 'desc';
}

export interface DeleteFilters {
  source?: 'ios' | 'backend' | 'web';
  level?: 'debug' | 'info' | 'warn' | 'error';
  older_than?: string; // ISO timestamp
}

function createTimeoutController(timeoutMs: number = REQUEST_TIMEOUT_MS): {
  controller: AbortController;
  timeoutId: ReturnType<typeof setTimeout>;
} {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
  return { controller, timeoutId };
}

export class DebugApiClient {
  public baseUrl: string;

  constructor(baseUrl: string = DEFAULT_API_URL) {
    this.baseUrl = baseUrl.replace(/\/$/, ''); // Remove trailing slash
  }

  /**
   * Query debug logs with optional filters
   */
  async getDebugLogs(filters: QueryFilters = {}): Promise<QueryLogsResponse> {
    const { controller, timeoutId } = createTimeoutController();

    try {
      const params = new URLSearchParams();

      if (filters.correlation_id) params.set('correlation_id', filters.correlation_id);
      if (filters.source) params.set('source', filters.source);
      if (filters.level) params.set('level', filters.level);
      if (filters.event) params.set('event', filters.event);
      if (filters.since) params.set('since', filters.since);
      if (filters.limit) params.set('limit', filters.limit.toString());
      if (filters.order) params.set('order', filters.order);

      const queryString = params.toString();
      const url = `${this.baseUrl}/api/v1/debug/logs${queryString ? `?${queryString}` : ''}`;

      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
        },
        signal: controller.signal,
      });

      if (!response.ok) {
        const errorText = await response.text().catch(() => 'Unknown error');
        throw new Error(`API error (${response.status}): ${errorText}`);
      }

      const json = (await response.json()) as { data: QueryLogsResponse };
      // Backend wraps response in { data: ... }
      return json.data;
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        throw new Error('Request timed out');
      }
      throw error;
    } finally {
      clearTimeout(timeoutId);
    }
  }

  /**
   * Delete debug logs with filters
   */
  async deleteDebugLogs(filters: DeleteFilters = {}): Promise<DeleteResponse> {
    const { controller, timeoutId } = createTimeoutController();

    try {
      const params = new URLSearchParams();

      if (filters.source) params.set('source', filters.source);
      if (filters.level) params.set('level', filters.level);
      if (filters.older_than) params.set('older_than', filters.older_than);

      const queryString = params.toString();
      const url = `${this.baseUrl}/api/v1/debug/logs${queryString ? `?${queryString}` : ''}`;

      const response = await fetch(url, {
        method: 'DELETE',
        headers: {
          'Accept': 'application/json',
        },
        signal: controller.signal,
      });

      if (!response.ok) {
        const errorText = await response.text().catch(() => 'Unknown error');
        throw new Error(`API error (${response.status}): ${errorText}`);
      }

      const json = (await response.json()) as { data: DeleteResponse };
      return json.data;
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        throw new Error('Request timed out');
      }
      throw error;
    } finally {
      clearTimeout(timeoutId);
    }
  }

  /**
   * Get aggregated log statistics
   */
  async getStats(): Promise<LogStatsResponse> {
    const { controller, timeoutId } = createTimeoutController();

    try {
      const url = `${this.baseUrl}/api/v1/debug/logs/stats`;

      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
        },
        signal: controller.signal,
      });

      if (!response.ok) {
        const errorText = await response.text().catch(() => 'Unknown error');
        throw new Error(`API error (${response.status}): ${errorText}`);
      }

      const json = (await response.json()) as { data: LogStatsResponse };
      return json.data;
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        throw new Error('Request timed out');
      }
      throw error;
    } finally {
      clearTimeout(timeoutId);
    }
  }
}

/**
 * Create a client instance with the given API URL
 */
export function createClient(apiUrl?: string): DebugApiClient {
  return new DebugApiClient(apiUrl || DEFAULT_API_URL);
}
