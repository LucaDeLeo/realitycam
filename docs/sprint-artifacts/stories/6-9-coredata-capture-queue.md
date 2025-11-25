# Story 6.9: CoreData Capture Queue

**Status:** Done
**Completed:** 2025-11-25
**Epic:** 6 - Native Swift Implementation
**Sprint:** Current

## Story Description
As a mobile user, I want my captures to persist locally with upload queue management so that captures survive app restarts and network interruptions.

## Acceptance Criteria

### AC1: Captures Persist Across App Restarts
- CaptureEntity stored in CoreData SQLite database
- All capture data (JPEG, depth, metadata, assertion) persisted
- Database uses iOS Data Protection (completeUntilFirstUserAuthentication)

### AC2: Status Tracking
- CaptureStatus tracks: pending, uploading, uploaded, failed
- Status transitions properly logged
- Attempt count tracked for retry logic

### AC3: Queue Operations
- Save new capture to queue
- Fetch pending captures for upload
- Update status after upload attempt
- Delete uploaded captures after configurable retention period

### AC4: Storage Quota Management
- Track total storage used by captures
- Warning at 500MB usage threshold
- Automatic cleanup of uploaded captures after 7 days

### AC5: Migration Support
- Lightweight migration enabled for future schema changes
- Schema version tracking

## Technical Notes

### Files to Create
- `ios/Rial/Core/Storage/CaptureStore.swift` - CoreData persistence
- `ios/Rial/Core/Storage/OfflineQueue.swift` - Queue management
- `ios/Rial/Models/RialModel.xcdatamodeld` - CoreData schema (manual)
- `ios/RialTests/Storage/CaptureStoreTests.swift` - Unit tests

### CoreData Entity: CaptureEntity
```swift
@objc(CaptureEntity)
public class CaptureEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var jpeg: Data
    @NSManaged public var depth: Data
    @NSManaged public var metadata: Data     // JSON-encoded
    @NSManaged public var assertion: Data?
    @NSManaged public var status: String     // CaptureStatus raw value
    @NSManaged public var createdAt: Date
    @NSManaged public var attemptCount: Int16
    @NSManaged public var lastAttemptAt: Date?
    @NSManaged public var serverCaptureId: UUID?
    @NSManaged public var verificationUrl: String?
    @NSManaged public var thumbnail: Data?
}
```

### Implementation Notes
- NSPersistentContainer with persistent store description
- Data protection: completeUntilFirstUserAuthentication
- Background context for save operations
- Main context for fetch operations
- Storage quota calculation via file system

## Dependencies
- Story 6.1: Native iOS Project (completed)

## Definition of Done
- [ ] CaptureStore saves/loads captures correctly
- [ ] OfflineQueue manages pending uploads
- [ ] Status transitions work as expected
- [ ] Storage quota warning at 500MB
- [ ] Captures deleted after 7 days post-upload
- [ ] Unit tests pass
- [ ] Build succeeds

## Estimation
- Points: 5
- Complexity: Medium
