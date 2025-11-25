import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    /// Completion handler for background URL session events
    var backgroundCompletionHandler: (() -> Void)?

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        backgroundCompletionHandler = completionHandler
    }
}
