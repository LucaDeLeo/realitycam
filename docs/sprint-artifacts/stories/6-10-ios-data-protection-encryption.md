# Story 6.10: iOS Data Protection Encryption

**Status:** Done
**Epic:** 6 - Native Swift Implementation
**Sprint:** Current
**Completed:** 2025-11-25

## Story Description
As a mobile user, I want my offline captures encrypted using iOS Data Protection so that my photo data remains secure even if the device is compromised.

## Acceptance Criteria

### AC1: AES-256-GCM Encryption
- Captures encrypted using CryptoKit AES-256-GCM
- Encryption key generated and stored in Keychain
- Key protected with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

### AC2: Transparent Encryption/Decryption
- Captures encrypted before saving to CoreData
- Captures decrypted when retrieved from store
- JPEG, depth, and metadata all encrypted

### AC3: Key Management
- Single encryption key per device
- Key generated on first capture if not exists
- Key persists across app reinstalls (Keychain)
- Key never leaves device

### AC4: File Protection
- CoreData SQLite file uses completeUntilFirstUserAuthentication
- Binary data stored externally also protected
- No plaintext capture data on disk

## Technical Notes

### Files to Create/Modify
- `ios/Rial/Core/Storage/CaptureEncryption.swift` - Encryption service
- `ios/Rial/Core/Storage/CaptureStore.swift` - Add encryption integration
- `ios/RialTests/Storage/CaptureEncryptionTests.swift` - Unit tests

### Encryption Flow
```swift
// Save with encryption
let key = try keychain.loadOrCreateEncryptionKey()
let encryptedJpeg = try CryptoService.encrypt(capture.jpeg, using: key)
let encryptedDepth = try CryptoService.encrypt(capture.depth, using: key)
entity.jpeg = encryptedJpeg
entity.depth = encryptedDepth

// Load with decryption
let key = try keychain.loadEncryptionKey()
let jpeg = try CryptoService.decrypt(entity.jpeg, using: key)
let depth = try CryptoService.decrypt(entity.depth, using: key)
```

### Security Notes
- Use CryptoKit for modern encryption API
- AES-GCM provides authentication (tamper detection)
- Nonce generated fresh for each encryption operation
- Data format: nonce + ciphertext + tag (combined by CryptoKit)

## Dependencies
- Story 6.3: CryptoKit Integration (completed)
- Story 6.4: Keychain Services Integration (completed)
- Story 6.9: CoreData Capture Queue (completed)

## Definition of Done
- [x] CaptureEncryption service encrypts/decrypts data
- [x] CaptureStore integrates encryption transparently
- [x] Key stored securely in Keychain
- [x] Unit tests verify encryption/decryption
- [x] Build succeeds

## Estimation
- Points: 3
- Complexity: Low (leverages existing CryptoService)
