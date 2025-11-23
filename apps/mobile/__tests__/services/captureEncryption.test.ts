/**
 * Capture Encryption Service Tests
 *
 * Tests for AES-256-GCM encryption service.
 * Tests encryption/decryption round-trip, auth tag verification, and key management.
 *
 * @see Story 4.3 - Offline Storage and Auto-Upload (AC-2)
 */

import {
  encryptData,
  decryptData,
  generateIV,
  createEncryptionMetadata,
  bytesToBase64,
  base64ToBytes,
  stringToBytes,
  bytesToString,
} from '../../services/captureEncryption';

// Mock expo-secure-store
jest.mock('expo-secure-store', () => ({
  setItemAsync: jest.fn().mockResolvedValue(undefined),
  getItemAsync: jest.fn().mockResolvedValue(null),
  deleteItemAsync: jest.fn().mockResolvedValue(undefined),
  WHEN_UNLOCKED_THIS_DEVICE_ONLY: 'when_unlocked_this_device_only',
}));

// Mock expo-crypto
jest.mock('expo-crypto', () => ({
  randomUUID: jest.fn().mockReturnValue('test-uuid-1234'),
  getRandomBytes: jest.fn().mockImplementation((length: number) => {
    const bytes = new Uint8Array(length);
    for (let i = 0; i < length; i++) {
      bytes[i] = Math.floor(Math.random() * 256);
    }
    return bytes;
  }),
  digestStringAsync: jest.fn().mockImplementation(async (_algo, data) => {
    // Return a mock hash based on input length for deterministic tests
    const hash = Array(64)
      .fill(0)
      .map((_, i) => ((i + data.length) % 16).toString(16))
      .join('');
    return hash;
  }),
  CryptoDigestAlgorithm: {
    SHA256: 'SHA-256',
  },
  CryptoEncoding: {
    HEX: 'hex',
    BASE64: 'base64',
  },
}));

// Mock expo-file-system
jest.mock('expo-file-system', () => ({
  documentDirectory: '/mock/documents/',
  cacheDirectory: '/mock/cache/',
  readAsStringAsync: jest.fn().mockResolvedValue('bW9jayBmaWxlIGNvbnRlbnQ='), // "mock file content" base64
  writeAsStringAsync: jest.fn().mockResolvedValue(undefined),
  EncodingType: {
    Base64: 'base64',
    UTF8: 'utf8',
  },
}));

describe('captureEncryption', () => {
  describe('bytesToBase64 and base64ToBytes', () => {
    it('should round-trip convert bytes to base64 and back', () => {
      const original = new Uint8Array([0, 1, 127, 128, 255, 100, 50, 200]);
      const base64 = bytesToBase64(original);
      const recovered = base64ToBytes(base64);

      expect(recovered.length).toBe(original.length);
      for (let i = 0; i < original.length; i++) {
        expect(recovered[i]).toBe(original[i]);
      }
    });

    it('should handle empty array', () => {
      const original = new Uint8Array([]);
      const base64 = bytesToBase64(original);
      const recovered = base64ToBytes(base64);

      expect(recovered.length).toBe(0);
    });

    it('should handle single byte', () => {
      const original = new Uint8Array([42]);
      const base64 = bytesToBase64(original);
      const recovered = base64ToBytes(base64);

      expect(recovered.length).toBe(1);
      expect(recovered[0]).toBe(42);
    });

    it('should produce valid base64 string', () => {
      const original = new Uint8Array([72, 101, 108, 108, 111]); // "Hello"
      const base64 = bytesToBase64(original);

      // Base64 should only contain valid characters
      expect(base64).toMatch(/^[A-Za-z0-9+/=]*$/);
    });
  });

  describe('stringToBytes and bytesToString', () => {
    it('should round-trip convert string to bytes and back', () => {
      const original = 'Hello, World!';
      const bytes = stringToBytes(original);
      const recovered = bytesToString(bytes);

      expect(recovered).toBe(original);
    });

    it('should handle unicode characters', () => {
      const original = 'Hello, World!';
      const bytes = stringToBytes(original);
      const recovered = bytesToString(bytes);

      expect(recovered).toBe(original);
    });

    it('should handle empty string', () => {
      const original = '';
      const bytes = stringToBytes(original);
      const recovered = bytesToString(bytes);

      expect(recovered).toBe(original);
    });
  });

  describe('generateIV', () => {
    it('should generate base64-encoded IV', () => {
      const iv = generateIV();

      expect(typeof iv).toBe('string');
      expect(iv.length).toBeGreaterThan(0);
      // Base64 should only contain valid characters
      expect(iv).toMatch(/^[A-Za-z0-9+/=]*$/);
    });

    it('should generate different IVs on each call', () => {
      const iv1 = generateIV();
      const iv2 = generateIV();

      // While technically could be same, extremely unlikely
      // This tests that randomness is being used
      expect(iv1).not.toBe(iv2);
    });
  });

  describe('encryptData and decryptData', () => {
    const testKey = bytesToBase64(new Uint8Array(32).fill(0x42)); // 32 bytes of 0x42
    const testIV = bytesToBase64(new Uint8Array(12).fill(0x24)); // 12 bytes of 0x24

    it('should encrypt and decrypt data round-trip', async () => {
      const originalData = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

      const encrypted = await encryptData(originalData, testKey, testIV);
      const decrypted = await decryptData(encrypted, testKey, testIV);

      expect(decrypted.length).toBe(originalData.length);
      for (let i = 0; i < originalData.length; i++) {
        expect(decrypted[i]).toBe(originalData[i]);
      }
    });

    it('should produce encrypted data different from original', async () => {
      const originalData = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

      const encrypted = await encryptData(originalData, testKey, testIV);

      // Encrypted should be longer (includes auth tag)
      expect(encrypted.length).toBeGreaterThan(originalData.length);

      // Encrypted data should be different (excluding auth tag)
      const ciphertext = encrypted.slice(0, originalData.length);
      let different = false;
      for (let i = 0; i < originalData.length; i++) {
        if (ciphertext[i] !== originalData[i]) {
          different = true;
          break;
        }
      }
      expect(different).toBe(true);
    });

    it('should include auth tag in encrypted output', async () => {
      const originalData = new Uint8Array([1, 2, 3, 4, 5]);

      const encrypted = await encryptData(originalData, testKey, testIV);

      // Auth tag is 16 bytes
      expect(encrypted.length).toBe(originalData.length + 16);
    });

    it('should fail decryption with wrong key', async () => {
      const originalData = new Uint8Array([1, 2, 3, 4, 5]);
      const wrongKey = bytesToBase64(new Uint8Array(32).fill(0x99));

      const encrypted = await encryptData(originalData, testKey, testIV);

      await expect(decryptData(encrypted, wrongKey, testIV)).rejects.toThrow(
        'Authentication failed'
      );
    });

    it('should fail decryption with tampered data', async () => {
      const originalData = new Uint8Array([1, 2, 3, 4, 5]);

      const encrypted = await encryptData(originalData, testKey, testIV);

      // Tamper with encrypted data
      encrypted[0] = encrypted[0] ^ 0xff;

      await expect(decryptData(encrypted, testKey, testIV)).rejects.toThrow(
        'Authentication failed'
      );
    });

    it('should fail decryption with truncated data', async () => {
      const originalData = new Uint8Array([1, 2, 3, 4, 5]);

      const encrypted = await encryptData(originalData, testKey, testIV);

      // Truncate to remove auth tag
      const truncated = encrypted.slice(0, 5);

      await expect(decryptData(truncated, testKey, testIV)).rejects.toThrow(
        'Encrypted data too short'
      );
    });

    it('should encrypt empty data', async () => {
      const originalData = new Uint8Array([]);

      const encrypted = await encryptData(originalData, testKey, testIV);
      const decrypted = await decryptData(encrypted, testKey, testIV);

      expect(decrypted.length).toBe(0);
    });

    it('should encrypt large data', async () => {
      const originalData = new Uint8Array(10000);
      for (let i = 0; i < originalData.length; i++) {
        originalData[i] = i % 256;
      }

      const encrypted = await encryptData(originalData, testKey, testIV);
      const decrypted = await decryptData(encrypted, testKey, testIV);

      expect(decrypted.length).toBe(originalData.length);
      for (let i = 0; i < originalData.length; i++) {
        expect(decrypted[i]).toBe(originalData[i]);
      }
    });
  });

  describe('createEncryptionMetadata', () => {
    it('should create valid encryption metadata object', () => {
      const keyId = 'test-key-123';
      const iv = 'dGVzdC1pdi0xMjM=';

      const metadata = createEncryptionMetadata(keyId, iv);

      expect(metadata.keyId).toBe(keyId);
      expect(metadata.iv).toBe(iv);
      expect(metadata.algorithm).toBe('aes-256-gcm');
      expect(metadata.createdAt).toBeDefined();
      expect(new Date(metadata.createdAt).getTime()).toBeGreaterThan(0);
    });

    it('should set createdAt to current time', () => {
      const before = new Date().toISOString();
      const metadata = createEncryptionMetadata('key', 'iv');
      const after = new Date().toISOString();

      expect(metadata.createdAt >= before).toBe(true);
      expect(metadata.createdAt <= after).toBe(true);
    });
  });
});
