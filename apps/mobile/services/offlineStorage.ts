/**
 * Offline Storage Service
 *
 * Manages encrypted local storage for offline captures.
 * Handles save, load, and file management operations.
 *
 * @see Story 4.3 - Offline Storage and Auto-Upload (AC-1, AC-2, AC-3)
 */

import * as FileSystem from 'expo-file-system/legacy';
import type { ProcessedCapture, OfflineCaptureMetadata } from '@realitycam/shared';
import {
  generateEncryptionKey,
  getEncryptionKey,
  generateIV,
  encryptFile,
  decryptFile,
  encryptData,
  decryptData,
  createEncryptionMetadata,
  bytesToBase64,
  base64ToBytes,
  stringToBytes,
  bytesToString,
} from './captureEncryption';

/**
 * Base directory for offline captures
 */
const CAPTURES_DIR = `${FileSystem.documentDirectory}captures/`;

/**
 * File names within capture directory
 */
const FILES = {
  PHOTO: 'photo.jpg.enc',
  DEPTH: 'depth.gz.enc',
  METADATA: 'metadata.json.enc',
  ENCRYPTION: 'encryption.json',
} as const;

/**
 * Ensure captures directory exists
 */
async function ensureCapturesDir(): Promise<void> {
  const dirInfo = await FileSystem.getInfoAsync(CAPTURES_DIR);
  if (!dirInfo.exists) {
    await FileSystem.makeDirectoryAsync(CAPTURES_DIR, { intermediates: true });
    console.log('[offlineStorage] Created captures directory');
  }
}

/**
 * Get capture directory path
 */
function getCaptureDir(captureId: string): string {
  return `${CAPTURES_DIR}${captureId}/`;
}

/**
 * Get full path for a capture file
 */
function getCaptureFilePath(captureId: string, fileName: string): string {
  return `${getCaptureDir(captureId)}${fileName}`;
}

/**
 * Save encryption metadata to capture directory
 */
async function saveEncryptionMetadata(
  captureId: string,
  metadata: OfflineCaptureMetadata
): Promise<void> {
  const path = getCaptureFilePath(captureId, FILES.ENCRYPTION);
  await FileSystem.writeAsStringAsync(path, JSON.stringify(metadata, null, 2));
}

/**
 * Load encryption metadata from capture directory
 */
async function loadEncryptionMetadata(captureId: string): Promise<OfflineCaptureMetadata | null> {
  const path = getCaptureFilePath(captureId, FILES.ENCRYPTION);

  try {
    const content = await FileSystem.readAsStringAsync(path);
    return JSON.parse(content) as OfflineCaptureMetadata;
  } catch (error) {
    console.warn('[offlineStorage] Failed to load encryption metadata:', captureId, error);
    return null;
  }
}

/**
 * Save a processed capture to local encrypted storage
 *
 * @param capture - ProcessedCapture to save
 * @param queuedAt - ISO timestamp when capture was queued
 * @returns OfflineCaptureMetadata with storage info
 */
export async function saveCaptureLocally(
  capture: ProcessedCapture,
  queuedAt: string
): Promise<OfflineCaptureMetadata> {
  console.log('[offlineStorage] Saving capture locally:', capture.id);

  // Ensure base directory exists
  await ensureCapturesDir();

  // Create capture directory
  const captureDir = getCaptureDir(capture.id);
  await FileSystem.makeDirectoryAsync(captureDir, { intermediates: true });

  // Generate encryption key and IV
  const keyId = await generateEncryptionKey();
  const iv = generateIV();
  const keyBase64 = await getEncryptionKey(keyId);

  if (!keyBase64) {
    throw new Error('Failed to retrieve generated encryption key');
  }

  // Encrypt and save photo
  const photoEncPath = getCaptureFilePath(capture.id, FILES.PHOTO);
  const photoSize = await encryptFile(capture.photoUri, photoEncPath, keyBase64, iv);

  // Encrypt and save depth map (already base64)
  const depthBytes = base64ToBytes(capture.compressedDepthMap);
  const depthEncrypted = await encryptData(depthBytes, keyBase64, iv);
  const depthEncPath = getCaptureFilePath(capture.id, FILES.DEPTH);
  await FileSystem.writeAsStringAsync(depthEncPath, bytesToBase64(depthEncrypted), {
    encoding: FileSystem.EncodingType.Base64,
  });
  const depthSize = depthEncrypted.length;

  // Encrypt and save metadata
  const metadataJson = JSON.stringify(capture.metadata);
  const metadataBytes = stringToBytes(metadataJson);
  const metadataEncrypted = await encryptData(metadataBytes, keyBase64, iv);
  const metadataEncPath = getCaptureFilePath(capture.id, FILES.METADATA);
  await FileSystem.writeAsStringAsync(metadataEncPath, bytesToBase64(metadataEncrypted), {
    encoding: FileSystem.EncodingType.Base64,
  });
  const metadataSize = metadataEncrypted.length;

  // Create encryption metadata
  const encryptionMeta = createEncryptionMetadata(keyId, iv);
  const totalSize = photoSize + depthSize + metadataSize;

  const offlineMetadata: OfflineCaptureMetadata = {
    captureId: capture.id,
    encryption: encryptionMeta,
    photoSize,
    depthSize,
    metadataSize,
    totalSize,
    queuedAt,
  };

  // Save encryption metadata (unencrypted)
  await saveEncryptionMetadata(capture.id, offlineMetadata);

  console.log('[offlineStorage] Capture saved successfully:', {
    id: capture.id,
    totalSize,
    keyId,
  });

  return offlineMetadata;
}

/**
 * Load a capture from local encrypted storage
 *
 * @param captureId - Capture ID to load
 * @returns ProcessedCapture with decrypted data, or null if not found/corrupted
 */
export async function loadCaptureFromStorage(captureId: string): Promise<ProcessedCapture | null> {
  console.log('[offlineStorage] Loading capture from storage:', captureId);

  // Load encryption metadata
  const offlineMetadata = await loadEncryptionMetadata(captureId);
  if (!offlineMetadata) {
    console.error('[offlineStorage] Missing encryption metadata for capture:', captureId);
    return null;
  }

  // Get encryption key
  const keyBase64 = await getEncryptionKey(offlineMetadata.encryption.keyId);
  if (!keyBase64) {
    console.error('[offlineStorage] Encryption key not found:', offlineMetadata.encryption.keyId);
    return null;
  }

  const iv = offlineMetadata.encryption.iv;

  try {
    // Decrypt photo - save to temp file for upload
    const photoEncPath = getCaptureFilePath(captureId, FILES.PHOTO);
    const photoBytes = await decryptFile(photoEncPath, keyBase64, iv);

    // Save decrypted photo to temp location for upload
    const tempPhotoUri = `${FileSystem.cacheDirectory}temp-${captureId}.jpg`;
    await FileSystem.writeAsStringAsync(tempPhotoUri, bytesToBase64(photoBytes), {
      encoding: FileSystem.EncodingType.Base64,
    });

    // Decrypt depth map
    const depthEncPath = getCaptureFilePath(captureId, FILES.DEPTH);
    const depthEncBase64 = await FileSystem.readAsStringAsync(depthEncPath, {
      encoding: FileSystem.EncodingType.Base64,
    });
    const depthEncBytes = base64ToBytes(depthEncBase64);
    const depthBytes = await decryptData(depthEncBytes, keyBase64, iv);
    const compressedDepthMap = bytesToBase64(depthBytes);

    // Decrypt metadata
    const metadataEncPath = getCaptureFilePath(captureId, FILES.METADATA);
    const metadataEncBase64 = await FileSystem.readAsStringAsync(metadataEncPath, {
      encoding: FileSystem.EncodingType.Base64,
    });
    const metadataEncBytes = base64ToBytes(metadataEncBase64);
    const metadataBytes = await decryptData(metadataEncBytes, keyBase64, iv);
    const metadataJson = bytesToString(metadataBytes);
    const metadata = JSON.parse(metadataJson);

    // Compute photo hash from decrypted bytes
    const photoHash = metadata.photo_hash;

    // Reconstruct ProcessedCapture
    const capture: ProcessedCapture = {
      id: captureId,
      photoUri: tempPhotoUri,
      photoHash,
      compressedDepthMap,
      depthDimensions: metadata.depth_map_dimensions,
      metadata,
      status: 'ready',
      createdAt: offlineMetadata.queuedAt,
    };

    console.log('[offlineStorage] Capture loaded successfully:', captureId);
    return capture;
  } catch (error) {
    console.error('[offlineStorage] Failed to load capture:', captureId, error);
    return null;
  }
}

/**
 * Check if a capture exists in local storage
 *
 * @param captureId - Capture ID to check
 * @returns True if capture directory exists with encryption metadata
 */
export async function captureExistsInStorage(captureId: string): Promise<boolean> {
  const encryptionPath = getCaptureFilePath(captureId, FILES.ENCRYPTION);
  const info = await FileSystem.getInfoAsync(encryptionPath);
  return info.exists;
}

/**
 * Get list of all capture IDs stored locally
 *
 * @returns Array of capture IDs
 */
export async function getStoredCaptureIds(): Promise<string[]> {
  await ensureCapturesDir();

  try {
    const entries = await FileSystem.readDirectoryAsync(CAPTURES_DIR);

    // Filter to only directories that have encryption.json
    const captureIds: string[] = [];
    for (const entry of entries) {
      const encryptionPath = getCaptureFilePath(entry, FILES.ENCRYPTION);
      const info = await FileSystem.getInfoAsync(encryptionPath);
      if (info.exists) {
        captureIds.push(entry);
      }
    }

    return captureIds;
  } catch (error) {
    console.warn('[offlineStorage] Failed to list captures:', error);
    return [];
  }
}

/**
 * Get metadata for all stored captures (without loading full data)
 *
 * @returns Array of offline capture metadata
 */
export async function getAllStoredCaptureMetadata(): Promise<OfflineCaptureMetadata[]> {
  const captureIds = await getStoredCaptureIds();
  const metadataList: OfflineCaptureMetadata[] = [];

  for (const captureId of captureIds) {
    const metadata = await loadEncryptionMetadata(captureId);
    if (metadata) {
      metadataList.push(metadata);
    }
  }

  // Sort by queuedAt (oldest first - FIFO)
  metadataList.sort((a, b) =>
    new Date(a.queuedAt).getTime() - new Date(b.queuedAt).getTime()
  );

  return metadataList;
}

/**
 * Delete a capture from local storage
 *
 * @param captureId - Capture ID to delete
 * @returns True if deleted successfully
 */
export async function deleteCaptureFromStorage(captureId: string): Promise<boolean> {
  const captureDir = getCaptureDir(captureId);

  try {
    const info = await FileSystem.getInfoAsync(captureDir);
    if (!info.exists) {
      console.log('[offlineStorage] Capture directory not found:', captureId);
      return true; // Already deleted
    }

    // Load metadata to get key ID for cleanup
    const metadata = await loadEncryptionMetadata(captureId);

    // Delete the capture directory and all contents
    await FileSystem.deleteAsync(captureDir, { idempotent: true });

    console.log('[offlineStorage] Deleted capture:', captureId);

    // Note: We don't delete the encryption key here - that's handled by captureCleanup
    // to allow for key reuse optimization in the future

    return true;
  } catch (error) {
    console.error('[offlineStorage] Failed to delete capture:', captureId, error);
    return false;
  }
}

/**
 * Clean up temporary decrypted files for a capture
 *
 * @param captureId - Capture ID
 */
export async function cleanupTempFiles(captureId: string): Promise<void> {
  const tempPhotoUri = `${FileSystem.cacheDirectory}temp-${captureId}.jpg`;

  try {
    const info = await FileSystem.getInfoAsync(tempPhotoUri);
    if (info.exists) {
      await FileSystem.deleteAsync(tempPhotoUri, { idempotent: true });
      console.log('[offlineStorage] Cleaned up temp file:', captureId);
    }
  } catch (error) {
    console.warn('[offlineStorage] Failed to cleanup temp file:', captureId, error);
  }
}

/**
 * Get total storage used by all offline captures
 *
 * @returns Total bytes used
 */
export async function getTotalStorageUsed(): Promise<number> {
  const metadataList = await getAllStoredCaptureMetadata();
  return metadataList.reduce((total, meta) => total + meta.totalSize, 0);
}

/**
 * Validate integrity of a stored capture
 *
 * @param captureId - Capture ID to validate
 * @returns True if capture appears valid
 */
export async function validateCaptureIntegrity(captureId: string): Promise<boolean> {
  const captureDir = getCaptureDir(captureId);

  try {
    // Check all required files exist
    for (const fileName of Object.values(FILES)) {
      const filePath = `${captureDir}${fileName}`;
      const info = await FileSystem.getInfoAsync(filePath);
      if (!info.exists) {
        console.warn('[offlineStorage] Missing file:', filePath);
        return false;
      }
    }

    // Verify encryption metadata is readable
    const metadata = await loadEncryptionMetadata(captureId);
    if (!metadata || !metadata.encryption.keyId || !metadata.encryption.iv) {
      console.warn('[offlineStorage] Invalid encryption metadata:', captureId);
      return false;
    }

    // Verify encryption key exists
    const key = await getEncryptionKey(metadata.encryption.keyId);
    if (!key) {
      console.warn('[offlineStorage] Encryption key missing:', metadata.encryption.keyId);
      return false;
    }

    return true;
  } catch (error) {
    console.warn('[offlineStorage] Integrity check failed:', captureId, error);
    return false;
  }
}

/**
 * Get captures directory path (for external access)
 */
export function getCapturesDirectory(): string {
  return CAPTURES_DIR;
}
