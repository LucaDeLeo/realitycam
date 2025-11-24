# TODO

Technical debt and future improvements tracked from hackathon cleanup.

## Backend

### Integration Tests
- **File**: `backend/tests/integration.rs`
- **Status**: Placeholder only
- **TODO**: Add real integration tests for:
  - Database operations
  - S3 storage operations
  - API endpoint integration

### Hash Security
- **File**: `backend/src/routes/captures.rs:323`
- **Issue**: Mobile hashes base64-encoded string instead of raw bytes
- **TODO**: Fix mobile to hash raw bytes instead for proper security

### Error Handling in main.rs
- Several `unwrap()` and `expect()` calls in startup code should be replaced with proper error handling and graceful exits

### Hardcoded Dev URL
- **File**: `backend/src/routes/verify.rs:366`
- **Issue**: Hardcoded `http://192.168.0.90:4566/...` LocalStack URL
- **TODO**: Make this configuration-driven for production

## Mobile

### Naming Consistency
- Consider standardizing LiDAR capitalization across the codebase:
  - `useLiDAR.ts` vs `lidarDetection.ts`
  - `checkLiDARAvailability()` vs `LIDAR_MODEL_PATTERNS`

## General

### TypeScript Version Alignment
- Mobile: `~5.9.2`, Web: `^5`, Shared: `^5.7.0`
- Consider aligning all packages to same version constraint

### Upload Status Naming
- `permanently_failed` uses snake_case while other statuses use camelCase
- Low priority: would be a breaking change to fix
