import UIKit
import os.log

// MARK: - AppDelegate

/// Application delegate handling background URLSession events.
///
/// Manages completion handlers for both photo and video upload services
/// when the app is woken from background or termination.
///
/// ## Background Session Handling
/// When iOS wakes the app to handle background URLSession events:
/// 1. This method is called with the session identifier
/// 2. We store the completion handler and route it to the appropriate service
/// 3. The service processes pending events
/// 4. Service calls the completion handler when done
///
/// ## Session Identifiers
/// - `app.rial.upload`: Photo capture uploads (UploadService)
/// - `app.rial.video-upload`: Video capture uploads (VideoUploadService)
class AppDelegate: NSObject, UIApplicationDelegate {
    private static let logger = Logger(subsystem: "app.rial", category: "app-delegate")

    /// Completion handler for photo upload background session
    var photoUploadCompletionHandler: (() -> Void)?

    /// Completion handler for video upload background session
    var videoUploadCompletionHandler: (() -> Void)?

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        Self.logger.info("Background session events received for identifier: \(identifier)")

        // Route to appropriate upload service based on session identifier
        switch identifier {
        case "app.rial.upload":
            // Photo upload service
            photoUploadCompletionHandler = completionHandler
            Self.logger.debug("Photo upload background completion handler stored")

        case VideoUploadService.sessionIdentifier:
            // Video upload service (Story 7-8)
            VideoUploadService.shared.backgroundCompletionHandler = completionHandler
            Self.logger.debug("Video upload background completion handler stored")

        default:
            // Unknown session - log warning and call completion immediately
            Self.logger.warning("Unknown background session identifier: \(identifier)")
            completionHandler()
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Self.logger.info("Application did finish launching")

        // Resume any pending video uploads from previous session
        Task {
            await VideoUploadService.shared.resumePendingUploads()
        }

        return true
    }
}
