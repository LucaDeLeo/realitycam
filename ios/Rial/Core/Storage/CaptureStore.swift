//
//  CaptureStore.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  CoreData persistence for capture queue management.
//

import Foundation
import CoreData
import os.log

/// CoreData-based persistence for captures with upload queue management.
///
/// Provides persistent storage for captures that survive app restarts, with
/// automatic status tracking and upload queue management.
///
/// ## Features
/// - SQLite-backed CoreData storage
/// - iOS Data Protection (completeUntilFirstUserAuthentication)
/// - Status tracking: pending, uploading, uploaded, failed
/// - Storage quota monitoring with warnings at 500MB
/// - Automatic cleanup of uploaded captures after 7 days
///
/// ## Thread Safety
/// - Uses main context for reads
/// - Uses background context for writes
/// - All operations are thread-safe
///
/// ## Example Usage
/// ```swift
/// let store = CaptureStore()
///
/// // Save a new capture
/// try await store.saveCapture(captureData)
///
/// // Get pending uploads
/// let pending = try await store.fetchPendingCaptures()
///
/// // Update status after upload
/// try await store.updateStatus(.uploaded, for: captureId)
/// ```
final class CaptureStore {
    private static let logger = Logger(subsystem: "app.rial", category: "capture-store")

    /// CoreData persistent container
    private let container: NSPersistentContainer

    /// Optional encryption service for at-rest encryption
    private let encryption: CaptureEncryption?

    /// Retention period for uploaded captures (7 days)
    private let retentionDays: Int = 7

    /// Storage warning threshold in bytes (500MB)
    private let storageWarningThreshold: Int64 = 500 * 1024 * 1024

    // MARK: - Initialization

    /// Creates a new CaptureStore with default configuration.
    ///
    /// Initializes CoreData stack with iOS Data Protection and
    /// lightweight migration support.
    ///
    /// - Parameters:
    ///   - inMemory: If true, uses in-memory store (for testing)
    ///   - encryption: Optional encryption service for at-rest encryption
    init(inMemory: Bool = false, encryption: CaptureEncryption? = nil) {
        self.encryption = encryption
        container = NSPersistentContainer(
            name: "RialModel",
            managedObjectModel: Self.createManagedObjectModel()
        )

        // Configure store description
        let description = NSPersistentStoreDescription()

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            let storeURL = Self.storeURL()
            description.url = storeURL
        }

        // Enable iOS Data Protection
        description.setOption(
            FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
            forKey: NSPersistentStoreFileProtectionKey
        )

        // Enable lightweight migration
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        container.persistentStoreDescriptions = [description]

        // Load persistent stores
        container.loadPersistentStores { [weak self] storeDescription, error in
            if let error = error {
                Self.logger.error("CoreData load failed: \(error.localizedDescription)")
                fatalError("CoreData load failed: \(error)")
            }

            Self.logger.info("CoreData store loaded: \(storeDescription.url?.absoluteString ?? "unknown")")

            // Run cleanup on startup
            Task {
                try? await self?.cleanupOldCaptures()
            }
        }

        // Configure contexts
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Public API

    /// Save a new capture to the store.
    ///
    /// Creates a CaptureEntity with pending status and stores all capture data.
    ///
    /// - Parameters:
    ///   - capture: CaptureData to save
    ///   - status: Initial status (defaults to .pending)
    /// - Throws: `CaptureStoreError` if save fails
    func saveCapture(_ capture: CaptureData, status: CaptureStatus = .pending) async throws {
        let context = container.newBackgroundContext()

        // Encrypt data if encryption service is available
        let jpegData: Data
        let depthData: Data
        let metadataData: Data
        let assertionData: Data?

        if let encryption = encryption {
            let metadata = try JSONEncoder().encode(capture.metadata)
            let encrypted = try encryption.encryptCapture(jpeg: capture.jpeg, depth: capture.depth, metadata: metadata)
            jpegData = encrypted.jpeg
            depthData = encrypted.depth
            metadataData = encrypted.metadata
            assertionData = try encryption.encrypt(optional: capture.assertion)
        } else {
            jpegData = capture.jpeg
            depthData = capture.depth
            metadataData = try JSONEncoder().encode(capture.metadata)
            assertionData = capture.assertion
        }

        try await context.perform {
            let entity = CaptureEntity(context: context)
            entity.id = capture.id
            entity.jpeg = jpegData
            entity.depth = depthData
            entity.metadata = metadataData
            entity.assertion = assertionData
            entity.assertionStatus = capture.assertionStatus.rawValue
            entity.status = status.rawValue
            entity.createdAt = capture.timestamp
            entity.attemptCount = 0
            entity.isEncrypted = self.encryption != nil

            try context.save()
        }

        Self.logger.info("Saved capture: \(capture.id.uuidString, privacy: .public) (encrypted: \(self.encryption != nil))")

        // Check storage quota after save
        await checkStorageQuota()
    }

    /// Fetch all captures with pending status.
    ///
    /// - Returns: Array of CaptureData ready for upload
    /// - Throws: `CaptureStoreError` if fetch fails
    func fetchPendingCaptures() async throws -> [CaptureData] {
        let context = container.viewContext

        return try await context.perform {
            let request = CaptureEntity.fetchRequest()
            request.predicate = NSPredicate(format: "status == %@", CaptureStatus.pending.rawValue)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CaptureEntity.createdAt, ascending: true)]

            let entities = try context.fetch(request)
            return try entities.map { try self.captureData(from: $0) }
        }
    }

    /// Fetch all captures (for history view).
    ///
    /// - Returns: Array of all captures, newest first
    func fetchAllCaptures() async throws -> [CaptureData] {
        let context = container.viewContext

        return try await context.perform {
            let request = CaptureEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CaptureEntity.createdAt, ascending: false)]

            let entities = try context.fetch(request)
            return try entities.map { try self.captureData(from: $0) }
        }
    }

    /// Fetch a single capture by ID.
    ///
    /// - Parameter id: Capture UUID
    /// - Returns: CaptureData if found, nil otherwise
    func fetchCapture(byId id: UUID) async throws -> CaptureData? {
        let context = container.viewContext

        return try await context.perform {
            let request = CaptureEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try context.fetch(request).first else {
                return nil
            }

            return try self.captureData(from: entity)
        }
    }

    /// Update capture status.
    ///
    /// - Parameters:
    ///   - status: New status
    ///   - captureId: Capture UUID
    /// - Throws: `CaptureStoreError.notFound` if capture doesn't exist
    func updateStatus(_ status: CaptureStatus, for captureId: UUID) async throws {
        let context = container.newBackgroundContext()

        try await context.perform {
            let request = CaptureEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", captureId as CVarArg)
            request.fetchLimit = 1

            guard let entity = try context.fetch(request).first else {
                throw CaptureStoreError.notFound
            }

            entity.status = status.rawValue

            if status == .uploading || status == .failed {
                entity.lastAttemptAt = Date()
                entity.attemptCount += 1
            }

            try context.save()
        }

        Self.logger.info("Updated capture \(captureId.uuidString, privacy: .public) status to \(status.rawValue)")
    }

    /// Update capture with server response after successful upload.
    ///
    /// - Parameters:
    ///   - captureId: Local capture UUID
    ///   - serverCaptureId: Server-assigned capture UUID
    ///   - verificationUrl: Verification page URL
    func updateUploadResult(
        for captureId: UUID,
        serverCaptureId: UUID,
        verificationUrl: String
    ) async throws {
        let context = container.newBackgroundContext()

        try await context.perform {
            let request = CaptureEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", captureId as CVarArg)
            request.fetchLimit = 1

            guard let entity = try context.fetch(request).first else {
                throw CaptureStoreError.notFound
            }

            entity.status = CaptureStatus.uploaded.rawValue
            entity.serverCaptureId = serverCaptureId
            entity.verificationUrl = verificationUrl
            entity.uploadedAt = Date()

            try context.save()
        }

        Self.logger.info("Upload complete for capture \(captureId.uuidString, privacy: .public)")
    }

    /// Delete a capture by ID.
    ///
    /// - Parameter id: Capture UUID
    func deleteCapture(byId id: UUID) async throws {
        let context = container.newBackgroundContext()

        try await context.perform {
            let request = CaptureEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try context.fetch(request).first else {
                return // Already deleted
            }

            context.delete(entity)
            try context.save()
        }

        Self.logger.info("Deleted capture: \(id.uuidString, privacy: .public)")
    }

    /// Get count of captures by status.
    ///
    /// - Parameter status: Status to count, or nil for all
    /// - Returns: Number of captures matching the status
    func captureCount(status: CaptureStatus? = nil) async throws -> Int {
        let context = container.viewContext

        return try await context.perform {
            let request = CaptureEntity.fetchRequest()
            if let status = status {
                request.predicate = NSPredicate(format: "status == %@", status.rawValue)
            }
            return try context.count(for: request)
        }
    }

    /// Calculate total storage used by captures.
    ///
    /// - Returns: Total bytes used
    func storageUsed() async throws -> Int64 {
        let context = container.viewContext

        return try await context.perform {
            let request = CaptureEntity.fetchRequest()
            let entities = try context.fetch(request)

            var total: Int64 = 0
            for entity in entities {
                total += Int64(entity.jpeg.count)
                total += Int64(entity.depth.count)
                total += Int64(entity.metadata.count)
                total += Int64(entity.assertion?.count ?? 0)
                total += Int64(entity.thumbnail?.count ?? 0)
            }

            return total
        }
    }

    // MARK: - Cleanup

    /// Delete uploaded captures older than retention period.
    ///
    /// Called automatically on startup.
    func cleanupOldCaptures() async throws {
        let context = container.newBackgroundContext()
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())!

        try await context.perform {
            let request = CaptureEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "status == %@ AND uploadedAt < %@",
                CaptureStatus.uploaded.rawValue,
                cutoffDate as CVarArg
            )

            let entities = try context.fetch(request)
            let count = entities.count

            for entity in entities {
                context.delete(entity)
            }

            if count > 0 {
                try context.save()
                Self.logger.info("Cleaned up \(count) old captures")
            }
        }
    }

    // MARK: - Private Helpers

    /// Check storage quota and log warning if exceeded.
    private func checkStorageQuota() async {
        do {
            let used = try await storageUsed()
            if used > storageWarningThreshold {
                let usedMB = Double(used) / 1024 / 1024
                Self.logger.warning("Storage quota warning: \(String(format: "%.1f", usedMB))MB used")
            }
        } catch {
            Self.logger.error("Failed to check storage quota: \(error.localizedDescription)")
        }
    }

    /// Convert CaptureEntity to CaptureData.
    private func captureData(from entity: CaptureEntity) throws -> CaptureData {
        // Decrypt if necessary
        let jpegData: Data
        let depthData: Data
        let metadataData: Data
        let assertionData: Data?

        if entity.isEncrypted, let encryption = encryption {
            let decrypted = try encryption.decryptCapture(
                jpeg: entity.jpeg,
                depth: entity.depth,
                metadata: entity.metadata
            )
            jpegData = decrypted.jpeg
            depthData = decrypted.depth
            metadataData = decrypted.metadata
            assertionData = try encryption.decrypt(optional: entity.assertion)
        } else {
            jpegData = entity.jpeg
            depthData = entity.depth
            metadataData = entity.metadata
            assertionData = entity.assertion
        }

        let metadata = try JSONDecoder().decode(CaptureMetadata.self, from: metadataData)

        return CaptureData(
            id: entity.id,
            jpeg: jpegData,
            depth: depthData,
            metadata: metadata,
            assertion: assertionData,
            assertionStatus: AssertionStatus(rawValue: entity.assertionStatus) ?? .none,
            assertionAttemptCount: Int(entity.attemptCount),
            timestamp: entity.createdAt
        )
    }

    /// Get store URL in documents directory.
    private static func storeURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Rial.sqlite")
    }

    // MARK: - Video Capture Methods (Story 7-8)

    /// Save a new video capture to the store.
    ///
    /// Creates a VideoCaptureEntity with pending_upload status.
    ///
    /// - Parameter capture: ProcessedVideoCapture to save
    /// - Throws: `CaptureStoreError` if save fails
    func saveVideoCapture(_ capture: ProcessedVideoCapture) async throws {
        let context = container.newBackgroundContext()

        try await context.perform {
            let entity = VideoCaptureEntity(context: context)
            entity.configure(from: capture)

            try context.save()
        }

        Self.logger.info("Saved video capture: \(capture.id.uuidString, privacy: .public)")

        // Check storage quota after save
        await checkStorageQuota()
    }

    /// Fetch a single video capture by ID.
    ///
    /// - Parameter id: Video capture UUID
    /// - Returns: ProcessedVideoCapture if found, nil otherwise
    func loadVideoCapture(id: UUID) async throws -> ProcessedVideoCapture? {
        let context = container.viewContext

        return try await context.perform {
            let request = VideoCaptureEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try context.fetch(request).first else {
                return nil
            }

            return entity.toProcessedVideoCapture()
        }
    }

    /// Update video capture status.
    ///
    /// - Parameters:
    ///   - status: New status
    ///   - captureId: Video capture UUID
    /// - Throws: `CaptureStoreError.notFound` if capture doesn't exist
    func updateVideoCaptureStatus(_ status: VideoCaptureStatus, for captureId: UUID) async throws {
        let context = container.newBackgroundContext()

        try await context.perform {
            let request = VideoCaptureEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", captureId as CVarArg)
            request.fetchLimit = 1

            guard let entity = try context.fetch(request).first else {
                throw CaptureStoreError.notFound
            }

            entity.status = status.rawValue

            if status == .uploading || status == .failed {
                entity.lastAttemptAt = Date()
                entity.attemptCount += 1
            }

            try context.save()
        }

        Self.logger.info("Updated video capture \(captureId.uuidString, privacy: .public) status to \(status.rawValue)")
    }

    /// Update video capture with server response after successful upload.
    ///
    /// - Parameters:
    ///   - captureId: Local video capture UUID
    ///   - serverCaptureId: Server-assigned capture UUID
    ///   - verificationUrl: Verification page URL
    func updateVideoUploadResult(
        for captureId: UUID,
        serverCaptureId: UUID,
        verificationUrl: String
    ) async throws {
        let context = container.newBackgroundContext()

        try await context.perform {
            let request = VideoCaptureEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", captureId as CVarArg)
            request.fetchLimit = 1

            guard let entity = try context.fetch(request).first else {
                throw CaptureStoreError.notFound
            }

            entity.status = VideoCaptureStatus.uploaded.rawValue
            entity.serverCaptureId = serverCaptureId
            entity.verificationUrl = verificationUrl
            entity.uploadedAt = Date()

            try context.save()
        }

        Self.logger.info("Video upload complete for capture \(captureId.uuidString, privacy: .public)")
    }

    /// Fetch all video captures with pending_upload or failed status.
    ///
    /// - Returns: Array of ProcessedVideoCapture ready for upload
    func pendingVideoUploads() async throws -> [ProcessedVideoCapture] {
        let context = container.viewContext

        return try await context.perform {
            let request = VideoCaptureEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "status == %@ OR status == %@",
                VideoCaptureStatus.pendingUpload.rawValue,
                VideoCaptureStatus.failed.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(keyPath: \VideoCaptureEntity.createdAt, ascending: true)]

            let entities = try context.fetch(request)
            return entities.filter { $0.canRetry || $0.status == VideoCaptureStatus.pendingUpload.rawValue }
                .map { $0.toProcessedVideoCapture() }
        }
    }

    /// Fetch all video captures (for history view).
    ///
    /// - Returns: Array of all video captures, newest first
    func fetchAllVideoCaptures() async throws -> [ProcessedVideoCapture] {
        let context = container.viewContext

        return try await context.perform {
            let request = VideoCaptureEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \VideoCaptureEntity.createdAt, ascending: false)]

            let entities = try context.fetch(request)
            return entities.map { $0.toProcessedVideoCapture() }
        }
    }

    /// Delete a video capture by ID.
    ///
    /// Also cleans up the local video file if it exists.
    ///
    /// - Parameter id: Video capture UUID
    func deleteVideoCapture(byId id: UUID) async throws {
        let context = container.newBackgroundContext()

        var videoURLToDelete: URL?

        try await context.perform {
            let request = VideoCaptureEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            guard let entity = try context.fetch(request).first else {
                return // Already deleted
            }

            videoURLToDelete = entity.videoURL

            context.delete(entity)
            try context.save()
        }

        // Clean up local video file
        if let url = videoURLToDelete {
            try? FileManager.default.removeItem(at: url)
            Self.logger.debug("Cleaned up video file for capture \(id.uuidString, privacy: .public)")
        }

        Self.logger.info("Deleted video capture: \(id.uuidString, privacy: .public)")
    }

    /// Get count of video captures by status.
    ///
    /// - Parameter status: Status to count, or nil for all
    /// - Returns: Number of video captures matching the status
    func videoCaptureCount(status: VideoCaptureStatus? = nil) async throws -> Int {
        let context = container.viewContext

        return try await context.perform {
            let request = VideoCaptureEntity.fetchRequest()
            if let status = status {
                request.predicate = NSPredicate(format: "status == %@", status.rawValue)
            }
            return try context.count(for: request)
        }
    }

    // MARK: - Private Model Creation

    /// Create managed object model programmatically.
    ///
    /// This avoids needing an .xcdatamodeld file.
    private static func createManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // CaptureEntity
        let captureEntity = NSEntityDescription()
        captureEntity.name = "CaptureEntity"
        captureEntity.managedObjectClassName = NSStringFromClass(CaptureEntity.self)

        // Attributes
        let idAttr = NSAttributeDescription()
        idAttr.name = "id"
        idAttr.attributeType = .UUIDAttributeType
        idAttr.isOptional = false

        let jpegAttr = NSAttributeDescription()
        jpegAttr.name = "jpeg"
        jpegAttr.attributeType = .binaryDataAttributeType
        jpegAttr.isOptional = false
        jpegAttr.allowsExternalBinaryDataStorage = true

        let depthAttr = NSAttributeDescription()
        depthAttr.name = "depth"
        depthAttr.attributeType = .binaryDataAttributeType
        depthAttr.isOptional = false
        depthAttr.allowsExternalBinaryDataStorage = true

        let metadataAttr = NSAttributeDescription()
        metadataAttr.name = "metadata"
        metadataAttr.attributeType = .binaryDataAttributeType
        metadataAttr.isOptional = false

        let assertionAttr = NSAttributeDescription()
        assertionAttr.name = "assertion"
        assertionAttr.attributeType = .binaryDataAttributeType
        assertionAttr.isOptional = true

        let assertionStatusAttr = NSAttributeDescription()
        assertionStatusAttr.name = "assertionStatus"
        assertionStatusAttr.attributeType = .stringAttributeType
        assertionStatusAttr.isOptional = false
        assertionStatusAttr.defaultValue = "none"

        let statusAttr = NSAttributeDescription()
        statusAttr.name = "status"
        statusAttr.attributeType = .stringAttributeType
        statusAttr.isOptional = false
        statusAttr.defaultValue = "pending"

        let createdAtAttr = NSAttributeDescription()
        createdAtAttr.name = "createdAt"
        createdAtAttr.attributeType = .dateAttributeType
        createdAtAttr.isOptional = false

        let attemptCountAttr = NSAttributeDescription()
        attemptCountAttr.name = "attemptCount"
        attemptCountAttr.attributeType = .integer16AttributeType
        attemptCountAttr.isOptional = false
        attemptCountAttr.defaultValue = 0

        let lastAttemptAtAttr = NSAttributeDescription()
        lastAttemptAtAttr.name = "lastAttemptAt"
        lastAttemptAtAttr.attributeType = .dateAttributeType
        lastAttemptAtAttr.isOptional = true

        let serverCaptureIdAttr = NSAttributeDescription()
        serverCaptureIdAttr.name = "serverCaptureId"
        serverCaptureIdAttr.attributeType = .UUIDAttributeType
        serverCaptureIdAttr.isOptional = true

        let verificationUrlAttr = NSAttributeDescription()
        verificationUrlAttr.name = "verificationUrl"
        verificationUrlAttr.attributeType = .stringAttributeType
        verificationUrlAttr.isOptional = true

        let uploadedAtAttr = NSAttributeDescription()
        uploadedAtAttr.name = "uploadedAt"
        uploadedAtAttr.attributeType = .dateAttributeType
        uploadedAtAttr.isOptional = true

        let thumbnailAttr = NSAttributeDescription()
        thumbnailAttr.name = "thumbnail"
        thumbnailAttr.attributeType = .binaryDataAttributeType
        thumbnailAttr.isOptional = true

        let isEncryptedAttr = NSAttributeDescription()
        isEncryptedAttr.name = "isEncrypted"
        isEncryptedAttr.attributeType = .booleanAttributeType
        isEncryptedAttr.isOptional = false
        isEncryptedAttr.defaultValue = false

        captureEntity.properties = [
            idAttr, jpegAttr, depthAttr, metadataAttr, assertionAttr,
            assertionStatusAttr, statusAttr, createdAtAttr, attemptCountAttr,
            lastAttemptAtAttr, serverCaptureIdAttr, verificationUrlAttr,
            uploadedAtAttr, thumbnailAttr, isEncryptedAttr
        ]

        // VideoCaptureEntity (Story 7-8)
        let videoCaptureEntity = createVideoCaptureEntityDescription()

        model.entities = [captureEntity, videoCaptureEntity]
        return model
    }
}

// MARK: - CaptureEntity

/// CoreData entity for persisted captures.
@objc(CaptureEntity)
public class CaptureEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var jpeg: Data
    @NSManaged public var depth: Data
    @NSManaged public var metadata: Data
    @NSManaged public var assertion: Data?
    @NSManaged public var assertionStatus: String
    @NSManaged public var status: String
    @NSManaged public var createdAt: Date
    @NSManaged public var attemptCount: Int16
    @NSManaged public var lastAttemptAt: Date?
    @NSManaged public var serverCaptureId: UUID?
    @NSManaged public var verificationUrl: String?
    @NSManaged public var uploadedAt: Date?
    @NSManaged public var thumbnail: Data?
    @NSManaged public var isEncrypted: Bool
}

extension CaptureEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CaptureEntity> {
        return NSFetchRequest<CaptureEntity>(entityName: "CaptureEntity")
    }

    /// CaptureStatus enum value
    var captureStatus: CaptureStatus {
        CaptureStatus(rawValue: status) ?? .pending
    }

    /// Whether this capture has been uploaded
    var isUploaded: Bool {
        status == CaptureStatus.uploaded.rawValue
    }

    /// Whether this capture can be retried
    var canRetry: Bool {
        status == CaptureStatus.failed.rawValue && attemptCount < 5
    }
}

// MARK: - CaptureStoreError

/// Errors that can occur during capture store operations.
enum CaptureStoreError: Error, LocalizedError {
    /// Capture not found in store
    case notFound

    /// Failed to save capture
    case saveFailed(Error)

    /// Failed to fetch captures
    case fetchFailed(Error)

    /// Failed to delete capture
    case deleteFailed(Error)

    /// Storage quota exceeded
    case quotaExceeded

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Capture not found in store"
        case .saveFailed(let error):
            return "Failed to save capture: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Failed to fetch captures: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete capture: \(error.localizedDescription)"
        case .quotaExceeded:
            return "Storage quota exceeded"
        }
    }
}
