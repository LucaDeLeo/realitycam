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

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        Self.logger.info("Background session events received for identifier: \(identifier)")

        // Route to appropriate upload service based on session identifier
        switch identifier {
        case UploadService.sessionIdentifier:
            // Photo upload service
            UploadService.shared.backgroundCompletionHandler = completionHandler
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

        // Configure upload services
        let captureStore = CaptureStore.shared
        let keychain = KeychainService()

        UploadService.shared.configure(
            baseURL: AppEnvironment.apiBaseURL,
            captureStore: captureStore,
            keychain: keychain
        )

        VideoUploadService.shared.configure(
            baseURL: AppEnvironment.apiBaseURL,
            captureStore: captureStore,
            keychain: keychain
        )

        // Register device with backend (if not already registered)
        Task {
            do {
                try await DeviceRegistrationService.shared.registerIfNeeded()
            } catch {
                Self.logger.error("Device registration failed: \(error.localizedDescription)")
                // Non-fatal - app can still capture, uploads will queue
            }
        }

        // Resume any pending uploads from previous session
        Task {
            await UploadService.shared.resumePendingUploads()
            await VideoUploadService.shared.resumePendingUploads()
        }

        return true
    }
}
