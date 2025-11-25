//
//  ZoomableImageView.swift
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Pinch-to-zoom image view for capture detail.
//

import SwiftUI

/// Zoomable image view with pinch and double-tap gestures.
///
/// Supports:
/// - Pinch-to-zoom (1x to 5x)
/// - Double-tap to toggle between 1x and 2x
/// - Pan when zoomed
///
/// ## Usage
/// ```swift
/// ZoomableImageView(image: uiImage)
/// ```
struct ZoomableImageView: View {
    let image: UIImage?

    /// Current zoom scale
    @State private var scale: CGFloat = 1.0

    /// Last stable scale (before gesture started)
    @State private var lastScale: CGFloat = 1.0

    /// Offset for panning
    @State private var offset: CGSize = .zero

    /// Last stable offset
    @State private var lastOffset: CGSize = .zero

    /// Minimum zoom scale
    private let minScale: CGFloat = 1.0

    /// Maximum zoom scale
    private let maxScale: CGFloat = 5.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(combinedGesture)
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                if scale > 1.0 {
                                    // Reset to 1x
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    // Zoom to 2x
                                    scale = 2.0
                                    lastScale = 2.0
                                }
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    placeholderView
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .clipped()
    }

    // MARK: - Gestures

    /// Combined pinch and drag gesture
    private var combinedGesture: some Gesture {
        SimultaneousGesture(magnificationGesture, dragGesture)
    }

    /// Magnification (pinch) gesture
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = lastScale * value
                scale = min(max(newScale, minScale), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                // Reset offset if zoomed out to 1x
                if scale <= 1.0 {
                    withAnimation(.spring()) {
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }

    /// Drag gesture for panning when zoomed
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Only allow pan when zoomed in
                guard scale > 1.0 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("No Image")
                        .foregroundColor(.secondary)
                }
            )
    }
}

// MARK: - Preview

#if DEBUG
struct ZoomableImageView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ZoomableImageView(image: nil)
                .frame(height: 300)
                .previewDisplayName("No Image")

            ZoomableImageView(image: UIImage(systemName: "photo.fill"))
                .frame(height: 300)
                .previewDisplayName("With Image")
        }
    }
}
#endif
