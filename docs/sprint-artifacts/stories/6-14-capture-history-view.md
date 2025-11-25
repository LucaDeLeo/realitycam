# Story 6.14: Capture History View

**Status:** Done
**Epic:** 6 - Native Swift Implementation
**Sprint:** Current

## Story Description
As a mobile user, I want to see my capture history with status indicators so that I can track my verified photos and retry failed uploads.

## Acceptance Criteria

### AC1: Grid Layout
- 3-column grid of capture thumbnails
- Adaptive layout for different screen sizes
- Smooth scrolling with LazyVGrid

### AC2: Status Badges
- Uploaded (green checkmark)
- Uploading (blue progress)
- Pending (gray clock)
- Failed (red exclamation)

### AC3: Sorting
- Sorted by date (newest first)
- Groups or section headers optional

### AC4: Empty State
- Clear messaging when no captures
- CTA button to start capturing

### AC5: Pull-to-Refresh
- Refreshable scroll view
- Retries failed uploads on pull

## Technical Notes

### Files to Create
- `ios/Rial/Features/History/HistoryView.swift` - Main history view
- `ios/Rial/Features/History/HistoryViewModel.swift` - View model with data loading
- `ios/Rial/Features/History/CaptureThumbnailView.swift` - Thumbnail cell
- `ios/Rial/Features/History/EmptyHistoryView.swift` - Empty state view

### SwiftUI Implementation
```swift
struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()

    let columns = [GridItem(.adaptive(minimum: 100))]

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.captures.isEmpty {
                    EmptyHistoryView()
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(viewModel.captures) { capture in
                            CaptureThumbnailView(capture: capture)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .refreshable {
                await viewModel.retryFailedUploads()
            }
        }
    }
}
```

## Dependencies
- Story 6.9: CoreData Capture Queue (completed)
- Story 6.11: URLSession Background Uploads (completed)

## Definition of Done
- [x] HistoryView displays capture grid
- [x] Status badges show correct states
- [x] Empty state shown when no captures
- [x] Pull-to-refresh retries failed uploads
- [x] Navigation to detail view works
- [x] Build succeeds

## Estimation
- Points: 3
- Complexity: Medium
