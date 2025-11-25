//
//  ARViewContainer.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  SwiftUI wrapper for ARKit camera preview.
//

import SwiftUI
import ARKit
import RealityKit
import os.log

/// SwiftUI wrapper for ARKit camera preview.
///
/// Displays the live AR camera feed with automatic handling of session lifecycle.
/// Used as the background layer in CaptureView with depth overlay on top.
///
/// ## Usage
/// ```swift
/// ARViewContainer(session: captureSession.arSession)
///     .ignoresSafeArea()
/// ```
struct ARViewContainer: UIViewRepresentable {
    private static let logger = Logger(subsystem: "app.rial", category: "arview-container")

    /// The ARSession to display
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView()

        arView.session = session
        arView.automaticallyUpdatesLighting = true
        arView.autoenablesDefaultLighting = true

        // Disable scene rendering (we just want camera feed)
        arView.scene = SCNScene()

        // Configure for camera feed display
        arView.rendersContinuously = true
        arView.antialiasingMode = .multisampling4X

        Self.logger.debug("ARSCNView created and configured")

        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Session updates handled by ARCaptureSession
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: ()) {
        Self.logger.debug("ARSCNView dismantled")
    }
}

/// Simple AR view using ARView from RealityKit (alternative implementation).
///
/// Use this if you need RealityKit features. Otherwise ARViewContainer with ARSCNView
/// is lighter weight for just camera display.
struct RealityKitViewContainer: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session = session
        arView.renderOptions = [.disablePersonOcclusion, .disableDepthOfField]
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Session updates handled externally
    }
}

// MARK: - Camera Permission View

/// View displayed when camera permission is not granted.
struct CameraPermissionView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 64))
                .foregroundColor(.gray)

            Text("Camera Access Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("RealityCam needs camera access to capture authenticated photos with LiDAR depth.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Button(action: openSettings) {
                Text("Open Settings")
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.top)
        }
        .padding()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// View displayed when LiDAR is not available on device.
struct LiDARUnavailableView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sensor.fill")
                .font(.system(size: 64))
                .foregroundColor(.orange)

            Text("LiDAR Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("RealityCam requires an iPhone Pro model with LiDAR sensor for authenticated depth capture.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Text("Compatible devices: iPhone 12 Pro and newer")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Preview

#if DEBUG
struct ARViewContainer_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CameraPermissionView()
                .previewDisplayName("Permission Needed")

            LiDARUnavailableView()
                .previewDisplayName("LiDAR Unavailable")
        }
    }
}
#endif
