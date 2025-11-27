//
//  VideoCaptureEntity.swift
//  Rial
//
//  Created by RealityCam on 2025-11-27.
//
//  CoreData entity for video capture persistence (Story 7-8).
//

import Foundation
import CoreData

// MARK: - VideoCaptureEntity

/// CoreData entity for persisted video captures.
///
/// Stores all components of a ProcessedVideoCapture for offline queue support
/// and upload resumption. Uses external binary data storage for large blobs.
///
/// ## Status Lifecycle
/// - `pending_upload`: Ready for upload
/// - `uploading`: Currently uploading
/// - `paused`: Upload paused (network unavailable, backgrounded)
/// - `uploaded`: Upload completed successfully
/// - `failed`: Upload failed after all retries
///
/// ## Usage
/// ```swift
/// let entity = VideoCaptureEntity(context: context)
/// entity.configure(from: processedCapture)
/// try context.save()
/// ```
@objc(VideoCaptureEntity)
public class VideoCaptureEntity: NSManagedObject, Identifiable {
    /// Unique identifier for this capture
    @NSManaged public var id: UUID

    /// URL to local video file (stored in app's Documents)
    @NSManaged public var videoURL: URL

    /// Gzip-compressed depth keyframe data
    @NSManaged public var compressedDepthData: Data

    /// Serialized hash chain as JSON
    @NSManaged public var hashChainJSON: Data

    /// Serialized metadata with attestation as JSON
    @NSManaged public var metadataJSON: Data

    /// JPEG thumbnail (optional, may be nil if generation failed)
    @NSManaged public var thumbnailData: Data?

    /// Upload status: pending_upload, uploading, paused, uploaded, failed
    @NSManaged public var status: String

    /// Frame count from recording (30fps)
    @NSManaged public var frameCount: Int32

    /// Depth keyframe count (10fps)
    @NSManaged public var depthKeyframeCount: Int32

    /// Duration in milliseconds
    @NSManaged public var durationMs: Int64

    /// Whether this is a partial (interrupted) recording
    @NSManaged public var isPartial: Bool

    /// Capture creation timestamp
    @NSManaged public var createdAt: Date

    /// Number of upload attempts
    @NSManaged public var attemptCount: Int16

    /// Last upload attempt timestamp
    @NSManaged public var lastAttemptAt: Date?

    /// Server-assigned capture UUID (after successful upload)
    @NSManaged public var serverCaptureId: UUID?

    /// Verification page URL (after successful upload)
    @NSManaged public var verificationUrl: String?

    /// When the upload completed successfully
    @NSManaged public var uploadedAt: Date?

    /// Whether data is encrypted at rest (reserved for future use)
    @NSManaged public var isEncrypted: Bool
}

// MARK: - Fetch Request

extension VideoCaptureEntity {
    /// Standard fetch request for VideoCaptureEntity
    @nonobjc public class func fetchRequest() -> NSFetchRequest<VideoCaptureEntity> {
        return NSFetchRequest<VideoCaptureEntity>(entityName: "VideoCaptureEntity")
    }
}

// MARK: - Convenience Properties

extension VideoCaptureEntity {
    /// VideoCaptureStatus enum value
    var captureStatus: VideoCaptureStatus {
        VideoCaptureStatus(rawValue: status) ?? .pendingUpload
    }

    /// Whether this capture has been uploaded
    var isUploaded: Bool {
        status == VideoCaptureStatus.uploaded.rawValue
    }

    /// Whether this capture can be retried
    var canRetry: Bool {
        (status == VideoCaptureStatus.failed.rawValue || status == VideoCaptureStatus.paused.rawValue)
            && attemptCount < 5
    }

    /// Total size of stored data in bytes (approximate)
    var totalSizeBytes: Int {
        let videoSize = (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int) ?? 0
        return videoSize
            + compressedDepthData.count
            + hashChainJSON.count
            + metadataJSON.count
            + (thumbnailData?.count ?? 0)
    }

    /// Human-readable size string
    var totalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSizeBytes), countStyle: .file)
    }

    /// Duration in seconds
    var durationSeconds: TimeInterval {
        TimeInterval(durationMs) / 1000.0
    }
}

// MARK: - Configuration from ProcessedVideoCapture

extension VideoCaptureEntity {
    /// Configure entity from a ProcessedVideoCapture.
    ///
    /// - Parameters:
    ///   - capture: The processed video capture to store
    ///   - initialStatus: Initial status (defaults to pending_upload)
    func configure(from capture: ProcessedVideoCapture, initialStatus: VideoCaptureStatus = .pendingUpload) {
        self.id = capture.id
        self.videoURL = capture.videoURL
        self.compressedDepthData = capture.compressedDepthData
        self.hashChainJSON = capture.hashChainJSON
        self.metadataJSON = capture.metadataJSON
        self.thumbnailData = capture.thumbnailData
        self.status = initialStatus.rawValue
        self.frameCount = Int32(capture.frameCount)
        self.depthKeyframeCount = Int32(capture.depthKeyframeCount)
        self.durationMs = capture.durationMs
        self.isPartial = capture.isPartial
        self.createdAt = capture.createdAt
        self.attemptCount = 0
        self.isEncrypted = false
    }

    /// Convert entity back to ProcessedVideoCapture.
    ///
    /// - Returns: ProcessedVideoCapture with current entity values
    func toProcessedVideoCapture() -> ProcessedVideoCapture {
        ProcessedVideoCapture(
            id: id,
            videoURL: videoURL,
            compressedDepthData: compressedDepthData,
            hashChainJSON: hashChainJSON,
            metadataJSON: metadataJSON,
            thumbnailData: thumbnailData ?? Data(),
            createdAt: createdAt,
            status: captureStatus,
            frameCount: Int(frameCount),
            depthKeyframeCount: Int(depthKeyframeCount),
            durationMs: durationMs,
            isPartial: isPartial
        )
    }
}

// MARK: - CoreData Model Description

/// Creates the VideoCaptureEntity description for programmatic CoreData model.
///
/// This is called from CaptureStore.createManagedObjectModel() to add
/// the video entity alongside the existing CaptureEntity.
///
/// - Returns: NSEntityDescription configured for VideoCaptureEntity
public func createVideoCaptureEntityDescription() -> NSEntityDescription {
    let entity = NSEntityDescription()
    entity.name = "VideoCaptureEntity"
    entity.managedObjectClassName = NSStringFromClass(VideoCaptureEntity.self)

    // ID attribute
    let idAttr = NSAttributeDescription()
    idAttr.name = "id"
    idAttr.attributeType = .UUIDAttributeType
    idAttr.isOptional = false

    // Video URL attribute
    let videoURLAttr = NSAttributeDescription()
    videoURLAttr.name = "videoURL"
    videoURLAttr.attributeType = .URIAttributeType
    videoURLAttr.isOptional = false

    // Compressed depth data attribute (external storage for large blobs)
    let compressedDepthAttr = NSAttributeDescription()
    compressedDepthAttr.name = "compressedDepthData"
    compressedDepthAttr.attributeType = .binaryDataAttributeType
    compressedDepthAttr.isOptional = false
    compressedDepthAttr.allowsExternalBinaryDataStorage = true

    // Hash chain JSON attribute
    let hashChainAttr = NSAttributeDescription()
    hashChainAttr.name = "hashChainJSON"
    hashChainAttr.attributeType = .binaryDataAttributeType
    hashChainAttr.isOptional = false

    // Metadata JSON attribute
    let metadataAttr = NSAttributeDescription()
    metadataAttr.name = "metadataJSON"
    metadataAttr.attributeType = .binaryDataAttributeType
    metadataAttr.isOptional = false

    // Thumbnail data attribute (optional)
    let thumbnailAttr = NSAttributeDescription()
    thumbnailAttr.name = "thumbnailData"
    thumbnailAttr.attributeType = .binaryDataAttributeType
    thumbnailAttr.isOptional = true

    // Status attribute
    let statusAttr = NSAttributeDescription()
    statusAttr.name = "status"
    statusAttr.attributeType = .stringAttributeType
    statusAttr.isOptional = false
    statusAttr.defaultValue = VideoCaptureStatus.pendingUpload.rawValue

    // Frame count attribute
    let frameCountAttr = NSAttributeDescription()
    frameCountAttr.name = "frameCount"
    frameCountAttr.attributeType = .integer32AttributeType
    frameCountAttr.isOptional = false
    frameCountAttr.defaultValue = 0

    // Depth keyframe count attribute
    let depthKeyframeCountAttr = NSAttributeDescription()
    depthKeyframeCountAttr.name = "depthKeyframeCount"
    depthKeyframeCountAttr.attributeType = .integer32AttributeType
    depthKeyframeCountAttr.isOptional = false
    depthKeyframeCountAttr.defaultValue = 0

    // Duration attribute
    let durationMsAttr = NSAttributeDescription()
    durationMsAttr.name = "durationMs"
    durationMsAttr.attributeType = .integer64AttributeType
    durationMsAttr.isOptional = false
    durationMsAttr.defaultValue = 0

    // Is partial attribute
    let isPartialAttr = NSAttributeDescription()
    isPartialAttr.name = "isPartial"
    isPartialAttr.attributeType = .booleanAttributeType
    isPartialAttr.isOptional = false
    isPartialAttr.defaultValue = false

    // Created at attribute
    let createdAtAttr = NSAttributeDescription()
    createdAtAttr.name = "createdAt"
    createdAtAttr.attributeType = .dateAttributeType
    createdAtAttr.isOptional = false

    // Attempt count attribute
    let attemptCountAttr = NSAttributeDescription()
    attemptCountAttr.name = "attemptCount"
    attemptCountAttr.attributeType = .integer16AttributeType
    attemptCountAttr.isOptional = false
    attemptCountAttr.defaultValue = 0

    // Last attempt at attribute
    let lastAttemptAtAttr = NSAttributeDescription()
    lastAttemptAtAttr.name = "lastAttemptAt"
    lastAttemptAtAttr.attributeType = .dateAttributeType
    lastAttemptAtAttr.isOptional = true

    // Server capture ID attribute
    let serverCaptureIdAttr = NSAttributeDescription()
    serverCaptureIdAttr.name = "serverCaptureId"
    serverCaptureIdAttr.attributeType = .UUIDAttributeType
    serverCaptureIdAttr.isOptional = true

    // Verification URL attribute
    let verificationUrlAttr = NSAttributeDescription()
    verificationUrlAttr.name = "verificationUrl"
    verificationUrlAttr.attributeType = .stringAttributeType
    verificationUrlAttr.isOptional = true

    // Uploaded at attribute
    let uploadedAtAttr = NSAttributeDescription()
    uploadedAtAttr.name = "uploadedAt"
    uploadedAtAttr.attributeType = .dateAttributeType
    uploadedAtAttr.isOptional = true

    // Is encrypted attribute
    let isEncryptedAttr = NSAttributeDescription()
    isEncryptedAttr.name = "isEncrypted"
    isEncryptedAttr.attributeType = .booleanAttributeType
    isEncryptedAttr.isOptional = false
    isEncryptedAttr.defaultValue = false

    entity.properties = [
        idAttr,
        videoURLAttr,
        compressedDepthAttr,
        hashChainAttr,
        metadataAttr,
        thumbnailAttr,
        statusAttr,
        frameCountAttr,
        depthKeyframeCountAttr,
        durationMsAttr,
        isPartialAttr,
        createdAtAttr,
        attemptCountAttr,
        lastAttemptAtAttr,
        serverCaptureIdAttr,
        verificationUrlAttr,
        uploadedAtAttr,
        isEncryptedAttr
    ]

    return entity
}
