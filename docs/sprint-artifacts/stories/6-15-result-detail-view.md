# Story 6.15: Result Detail View

**Status:** Done
**Epic:** 6 - Native Swift Implementation
**Sprint:** Current

## Story Description
As a mobile user, I want to see detailed information about my captured photo including the verification result, confidence level, and evidence summary so that I can share proof of authenticity.

## Acceptance Criteria

### AC1: Full Photo Display
- Full-resolution photo with pinch-to-zoom
- Smooth gesture handling
- Double-tap to reset zoom

### AC2: Confidence Badge
- HIGH (green) - verified authentic
- MEDIUM (yellow) - some verification
- LOW/SUSPICIOUS (red) - verification concerns
- Display when upload complete

### AC3: Evidence Summary
- Show attestation status
- Show depth analysis result
- Show metadata validation status
- Link to web verification page

### AC4: Share Functionality
- Share button in toolbar
- Shares verification URL
- Copy link option

### AC5: Status Display
- Upload progress for pending captures
- Retry button for failed uploads
- Verification URL for completed uploads

## Technical Notes

### Files to Create
- `ios/Rial/Features/Result/ResultDetailView.swift` - Main detail view
- `ios/Rial/Features/Result/ConfidenceBadge.swift` - Confidence level badge
- `ios/Rial/Features/Result/EvidenceSummaryView.swift` - Evidence details
- `ios/Rial/Features/Result/ZoomableImageView.swift` - Pinch-to-zoom image

### SwiftUI Implementation
```swift
struct ResultDetailView: View {
    let capture: CaptureHistoryItem
    @State private var showShareSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZoomableImageView(image: capture.thumbnail)

                if capture.status == .uploaded {
                    ConfidenceBadge(level: capture.confidenceLevel)
                    EvidenceSummaryView(capture: capture)
                } else {
                    StatusView(status: capture.status)
                }
            }
        }
        .navigationTitle("Capture Details")
        .toolbar {
            if let url = capture.verificationUrl {
                ShareLink(item: url)
            }
        }
    }
}
```

## Dependencies
- Story 6.14: Capture History View (completed)
- Story 6.11: URLSession Background Uploads (completed)

## Definition of Done
- [x] ResultDetailView displays photo with zoom
- [x] Confidence badge shows correct level
- [x] Evidence summary shows for uploaded captures
- [x] Share button works with verification URL
- [x] Status shown for pending/failed captures
- [x] Build succeeds

## Estimation
- Points: 3
- Complexity: Medium
