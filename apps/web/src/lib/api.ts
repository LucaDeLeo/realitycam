import type { ApiResponse, ApiError, Capture } from '@realitycam/shared';

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:8080';

export class ApiClient {
  private baseUrl: string;

  constructor(baseUrl: string = API_URL) {
    this.baseUrl = baseUrl;
  }

  async getCapture(id: string): Promise<ApiResponse<Capture>> {
    const response = await fetch(`${this.baseUrl}/api/v1/captures/${id}`);
    if (!response.ok) {
      const error: ApiError = await response.json();
      throw new Error(error.error.message);
    }
    return response.json();
  }

  async verifyCapture(id: string): Promise<ApiResponse<Capture>> {
    const response = await fetch(`${this.baseUrl}/api/v1/captures/${id}/verify`);
    if (!response.ok) {
      const error: ApiError = await response.json();
      throw new Error(error.error.message);
    }
    return response.json();
  }
}

export const apiClient = new ApiClient();
