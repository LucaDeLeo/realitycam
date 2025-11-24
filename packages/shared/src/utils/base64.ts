/**
 * Base64 Encoding/Decoding Utilities
 *
 * React Native compatible base64 conversion functions.
 * These implementations don't rely on btoa/atob which aren't
 * available in all React Native environments.
 */

const BASE64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

/**
 * Convert Uint8Array to base64 string
 *
 * @param bytes - Uint8Array to encode
 * @returns Base64 encoded string
 */
export function bytesToBase64(bytes: Uint8Array): string {
  let result = '';
  const len = bytes.length;

  for (let i = 0; i < len; i += 3) {
    const b1 = bytes[i];
    const b2 = i + 1 < len ? bytes[i + 1] : 0;
    const b3 = i + 2 < len ? bytes[i + 2] : 0;

    result += BASE64_CHARS[b1 >> 2];
    result += BASE64_CHARS[((b1 & 3) << 4) | (b2 >> 4)];
    result += i + 1 < len ? BASE64_CHARS[((b2 & 15) << 2) | (b3 >> 6)] : '=';
    result += i + 2 < len ? BASE64_CHARS[b3 & 63] : '=';
  }

  return result;
}

/**
 * Convert base64 string to Uint8Array
 *
 * @param base64 - Base64 encoded string
 * @returns Decoded Uint8Array
 */
export function base64ToBytes(base64: string): Uint8Array {
  // Remove padding
  const cleanBase64 = base64.replace(/=/g, '');
  const len = cleanBase64.length;

  // Calculate output length
  const outputLen = Math.floor((len * 3) / 4);
  const bytes = new Uint8Array(outputLen);

  let p = 0;
  for (let i = 0; i < len; i += 4) {
    const c1 = BASE64_CHARS.indexOf(cleanBase64[i]);
    const c2 = i + 1 < len ? BASE64_CHARS.indexOf(cleanBase64[i + 1]) : 0;
    const c3 = i + 2 < len ? BASE64_CHARS.indexOf(cleanBase64[i + 2]) : 0;
    const c4 = i + 3 < len ? BASE64_CHARS.indexOf(cleanBase64[i + 3]) : 0;

    if (p < outputLen) bytes[p++] = (c1 << 2) | (c2 >> 4);
    if (p < outputLen) bytes[p++] = ((c2 & 15) << 4) | (c3 >> 2);
    if (p < outputLen) bytes[p++] = ((c3 & 3) << 6) | c4;
  }

  return bytes;
}

// Aliases for backwards compatibility
export const uint8ArrayToBase64 = bytesToBase64;
export const base64ToUint8Array = base64ToBytes;
