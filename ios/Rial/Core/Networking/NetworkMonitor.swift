//
//  NetworkMonitor.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Network reachability monitoring for connectivity awareness.
//

import Foundation
import Network
import os.log
import Combine

/// Monitors network connectivity status.
///
/// Uses NWPathMonitor to track network reachability changes and notify
/// observers when connectivity is restored or lost.
///
/// ## Features
/// - Real-time connectivity monitoring
/// - Connection type detection (WiFi, cellular)
/// - Expensive network detection (cellular, hotspot)
/// - Publisher for reactive updates
///
/// ## Usage
/// ```swift
/// let monitor = NetworkMonitor.shared
/// monitor.start()
///
/// // Check current status
/// if monitor.isConnected {
///     try await upload()
/// }
///
/// // React to changes
/// monitor.onStatusChange = { status in
///     if status == .connected {
///         retryFailedUploads()
///     }
/// }
/// ```
final class NetworkMonitor: ObservableObject {
    private static let logger = Logger(subsystem: "app.rial", category: "network-monitor")

    /// Shared singleton instance
    static let shared = NetworkMonitor()

    /// The underlying NWPathMonitor
    private let monitor: NWPathMonitor

    /// Queue for monitor callbacks
    private let queue = DispatchQueue(label: "app.rial.network-monitor", qos: .utility)

    /// Current network status
    @Published private(set) var status: NetworkStatus = .unknown

    /// Current network path
    private(set) var currentPath: NWPath?

    /// Whether network is currently connected
    var isConnected: Bool {
        status == .connected
    }

    /// Whether connection is expensive (cellular, hotspot)
    var isExpensive: Bool {
        currentPath?.isExpensive ?? true
    }

    /// Whether connection is constrained (low data mode)
    var isConstrained: Bool {
        currentPath?.isConstrained ?? false
    }

    /// Current connection type
    var connectionType: ConnectionType {
        guard let path = currentPath else { return .unknown }

        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else {
            return .other
        }
    }

    /// Callback for status changes
    var onStatusChange: ((NetworkStatus) -> Void)?

    // MARK: - Initialization

    init() {
        monitor = NWPathMonitor()
    }

    deinit {
        stop()
    }

    // MARK: - Control Methods

    /// Start monitoring network status.
    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }

        monitor.start(queue: queue)
        Self.logger.info("Network monitoring started")
    }

    /// Stop monitoring network status.
    func stop() {
        monitor.cancel()
        Self.logger.info("Network monitoring stopped")
    }

    // MARK: - Private Methods

    private func handlePathUpdate(_ path: NWPath) {
        let oldStatus = status
        currentPath = path

        let newStatus: NetworkStatus = path.status == .satisfied ? .connected : .disconnected

        // Only notify if status changed
        guard newStatus != oldStatus else { return }

        DispatchQueue.main.async { [weak self] in
            self?.status = newStatus
            self?.onStatusChange?(newStatus)
        }

        Self.logger.info("Network status changed: \(oldStatus.rawValue) -> \(newStatus.rawValue)")

        if newStatus == .connected {
            logConnectionDetails(path)
        }
    }

    private func logConnectionDetails(_ path: NWPath) {
        var interfaces: [String] = []

        if path.usesInterfaceType(.wifi) { interfaces.append("WiFi") }
        if path.usesInterfaceType(.cellular) { interfaces.append("Cellular") }
        if path.usesInterfaceType(.wiredEthernet) { interfaces.append("Ethernet") }
        if path.usesInterfaceType(.loopback) { interfaces.append("Loopback") }
        if path.usesInterfaceType(.other) { interfaces.append("Other") }

        let details = [
            "interfaces: \(interfaces.joined(separator: ", "))",
            "expensive: \(path.isExpensive)",
            "constrained: \(path.isConstrained)"
        ].joined(separator: ", ")

        Self.logger.debug("Connection details: \(details)")
    }

    // MARK: - Convenience Methods

    /// Wait for network connectivity.
    ///
    /// - Parameter timeout: Maximum time to wait
    /// - Returns: `true` if connected, `false` if timeout
    func waitForConnection(timeout: TimeInterval = 30) async -> Bool {
        if isConnected { return true }

        return await withCheckedContinuation { continuation in
            var completed = false
            let lock = NSLock()

            // Set up timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                lock.lock()
                guard !completed else {
                    lock.unlock()
                    return
                }
                completed = true
                lock.unlock()
                continuation.resume(returning: false)
            }

            // Watch for connection
            let previousHandler = onStatusChange
            onStatusChange = { [weak self] status in
                previousHandler?(status)

                if status == .connected {
                    lock.lock()
                    guard !completed else {
                        lock.unlock()
                        return
                    }
                    completed = true
                    lock.unlock()

                    // Cancel timeout (can't actually cancel but flag prevents double resume)
                    self?.onStatusChange = previousHandler
                    continuation.resume(returning: true)
                }
            }
        }
    }
}

// MARK: - NetworkStatus

/// Network connectivity status.
enum NetworkStatus: String {
    /// Network status is unknown (monitoring not started)
    case unknown

    /// Network is connected
    case connected

    /// Network is disconnected
    case disconnected
}

// MARK: - ConnectionType

/// Type of network connection.
enum ConnectionType: String {
    /// WiFi connection
    case wifi

    /// Cellular connection
    case cellular

    /// Wired ethernet
    case ethernet

    /// Other connection type
    case other

    /// Unknown connection type
    case unknown
}
