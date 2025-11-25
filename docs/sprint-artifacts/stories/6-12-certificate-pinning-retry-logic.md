# Story 6.12: Certificate Pinning & Retry Logic

**Status:** Done
**Epic:** 6 - Native Swift Implementation
**Sprint:** Current

## Story Description
As a mobile user, I want my API connections to be secured with certificate pinning and automatic retry logic so that my data is protected from man-in-the-middle attacks and temporary network issues don't prevent successful uploads.

## Acceptance Criteria

### AC1: Certificate Pinning
- Server certificate verified against pinned public key
- Pinning failure rejects connection immediately
- TLS 1.3 minimum enforced
- Supports backup pins for key rotation

### AC2: Retry Logic
- Exponential backoff: 1s, 2s, 4s, 8s, 16s
- Max 5 attempts before marking as failed
- Jitter added to prevent thundering herd
- Only retryable errors trigger retry (network, 5xx)

### AC3: Network Reachability
- Network reachability changes trigger retry of failed uploads
- Offline state tracked for UI feedback
- Queued uploads resume when network available

## Technical Notes

### Files to Create/Modify
- `ios/Rial/Core/Networking/CertificatePinning.swift` - SSL pinning delegate
- `ios/Rial/Core/Networking/RetryManager.swift` - Exponential backoff logic
- `ios/Rial/Core/Networking/NetworkMonitor.swift` - Reachability tracking
- `ios/RialTests/Networking/RetryManagerTests.swift` - Unit tests

### Pinned Key Configuration
```swift
// SHA-256 of server's public key SPKI
let pinnedPublicKeyHash = "sha256/..."
```

### Exponential Backoff Formula
```
delay = min(baseDelay * 2^attempt, maxDelay) + jitter
```

## Dependencies
- Story 6.11: URLSession Background Uploads (completed)

## Definition of Done
- [x] CertificatePinning validates server certificate
- [x] RetryManager implements exponential backoff
- [x] NetworkMonitor tracks reachability status
- [x] Unit tests verify retry logic (35 tests passing)
- [x] Build succeeds

## Estimation
- Points: 3
- Complexity: Medium (TLS, retry patterns)
