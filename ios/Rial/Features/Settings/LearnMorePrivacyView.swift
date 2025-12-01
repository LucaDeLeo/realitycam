//
//  LearnMorePrivacyView.swift
//  Rial
//
//  Created by RealityCam on 2025-12-01.
//
//  Learn More sheet explaining privacy mode for Story 8-2.
//  Provides detailed explanation of trust model and trade-offs.
//

import SwiftUI

// MARK: - LearnMorePrivacyView

/// Sheet view explaining privacy mode, trust model, and trade-offs.
///
/// ## Content (AC #6)
/// - Trust model explanation: hardware attestation proves device computed analysis
/// - What is/isn't uploaded in hash-only mode
/// - Trade-offs: no server-side re-analysis possible
///
/// ## Usage
/// ```swift
/// .sheet(isPresented: $showLearnMore) {
///     LearnMorePrivacyView()
/// }
/// ```
public struct LearnMorePrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        navigationContent
    }

    @ViewBuilder
    private var navigationContent: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                scrollContent
            }
        } else {
            NavigationView {
                scrollContent
            }
            .navigationViewStyle(.stack)
        }
    }

    private var scrollContent: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    headerSection

                    Divider()

                    // How It Works
                    howItWorksSection

                    Divider()

                    // What Gets Uploaded
                    whatGetsUploadedSection

                    Divider()

                    // Trust Model
                    trustModelSection

                    Divider()

                    // Trade-offs
                    tradeOffsSection

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Privacy Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .center, spacing: 16) {
            Image(systemName: "shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .accessibilityHidden(true)

            Text("Your Media, Your Control")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("Privacy Mode keeps your photos and videos on your device while still providing verified authenticity.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("How It Works", systemImage: "gearshape.2")

            bulletPoint(
                "1.",
                "Your device captures a photo or video with LiDAR depth data"
            )

            bulletPoint(
                "2.",
                "Depth analysis runs locally on your device using the same algorithm as our servers"
            )

            bulletPoint(
                "3.",
                "Your device creates a cryptographic hash of the media"
            )

            bulletPoint(
                "4.",
                "Only the hash and analysis results are uploaded, never the actual media"
            )

            bulletPoint(
                "5.",
                "Hardware attestation proves your device performed the analysis"
            )
        }
    }

    private var whatGetsUploadedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("What Gets Uploaded", systemImage: "icloud.and.arrow.up")

            // Uploaded items
            VStack(alignment: .leading, spacing: 8) {
                Text("Uploaded:")
                    .font(.subheadline.bold())
                    .foregroundColor(.green)

                comparisonItem("Cryptographic hash of your media", uploaded: true)
                comparisonItem("Depth analysis results (computed locally)", uploaded: true)
                comparisonItem("Hardware attestation signature", uploaded: true)
                comparisonItem("Selected metadata (based on your settings)", uploaded: true)
            }

            // Not uploaded items
            VStack(alignment: .leading, spacing: 8) {
                Text("Never Uploaded:")
                    .font(.subheadline.bold())
                    .foregroundColor(.red)

                comparisonItem("Your actual photo or video", uploaded: false)
                comparisonItem("Raw depth map data", uploaded: false)
                comparisonItem("Any data you've disabled in settings", uploaded: false)
            }
        }
    }

    private var trustModelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Trust Model", systemImage: "checkmark.shield")

            Text("Privacy Mode uses Apple's DCAppAttest to prove that:")
                .font(.body)
                .foregroundColor(.secondary)

            bulletPoint(
                nil,
                "The analysis was performed by the genuine rial.app"
            )

            bulletPoint(
                nil,
                "The analysis ran on your actual iPhone with LiDAR"
            )

            bulletPoint(
                nil,
                "The results haven't been tampered with"
            )

            infoBox(
                "This hardware-based attestation means verifiers can trust the depth analysis results without ever seeing your original media."
            )
        }
    }

    private var tradeOffsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Trade-offs", systemImage: "scale.3d")

            Text("Privacy Mode has some limitations:")
                .font(.body)
                .foregroundColor(.secondary)

            tradeOffItem(
                "No server re-analysis",
                "If our algorithm improves, we can't re-analyze your capture"
            )

            tradeOffItem(
                "Hash verification only",
                "Verifiers can confirm the hash matches, but can't view the media"
            )

            tradeOffItem(
                "Local storage required",
                "Keep your original media if you want to share it later"
            )

            infoBox(
                "For most use cases, these trade-offs are worth the enhanced privacy. Choose standard mode if you need full server-side analysis capabilities."
            )
        }
    }

    // MARK: - Helper Views

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(.blue)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
        }
    }

    private func bulletPoint(_ number: String?, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let number = number {
                Text(number)
                    .font(.subheadline.bold())
                    .foregroundColor(.blue)
                    .frame(width: 20)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
                    .frame(width: 20)
            }
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func comparisonItem(_ text: String, uploaded: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: uploaded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(uploaded ? .green : .red)
                .font(.caption)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .accessibilityLabel("\(text), \(uploaded ? "uploaded" : "not uploaded")")
    }

    private func tradeOffItem(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.bold())
            }
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 24)
        }
        .accessibilityElement(children: .combine)
    }

    private func infoBox(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.yellow)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#if DEBUG
struct LearnMorePrivacyView_Previews: PreviewProvider {
    static var previews: some View {
        LearnMorePrivacyView()
    }
}
#endif
