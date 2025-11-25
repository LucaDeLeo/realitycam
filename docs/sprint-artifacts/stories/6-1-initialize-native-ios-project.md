# Story 6.1: Initialize Native iOS Project

**Story Key:** 6-1-initialize-native-ios-project
**Epic:** 6 - Native Swift Implementation
**Status:** Drafted
**Created:** 2025-11-25

---

## User Story

As a **developer**,
I want **the Rial iOS project created with proper Swift structure**,
So that **I can implement native security features without React Native overhead**.

## Story Context

This is the foundational story for Epic 6 - Native Swift Implementation. It establishes the Xcode project structure, capabilities, and folder organization that all subsequent native iOS stories will build upon.

Epic 6 re-implements the iOS mobile app in pure native Swift/SwiftUI, eliminating React Native/Expo to achieve maximum security posture through direct OS framework access. This story creates the clean project foundation enabling:
- Direct Secure Enclave access for cryptographic operations
- Unified RGB+depth capture with perfect synchronization
- Background uploads that survive app termination
- Zero external dependencies (minimal attack surface)

## Technical Background

### Why Native Swift Over React Native

| Aspect | React Native | Native Swift | Benefit |
|--------|-------------|--------------|---------|
| JS Bridge | Photo bytes cross boundary | All processing in native memory | Eliminates data exposure |
| Cryptography | SHA-256 stream cipher workaround | Real AES-GCM via CryptoKit | Authenticated encryption |
| Camera/Depth Sync | Two modules + JS coordination | Single ARFrame (same instant) | Perfect synchronization |
| Background Uploads | Foreground only | URLSession continues after termination | Reliable delivery |
| Dependencies | npm + native modules | Zero external packages | Minimal attack surface |

### Technical Requirements

- **Xcode 16+** with Swift 5.9+ compiler
- **iOS 15.0** minimum deployment target
- **SwiftUI** app lifecycle
- **App Attest** capability enabled
- Test targets for unit and UI testing

---

## Acceptance Criteria

### AC1: Xcode Project Creation
**Given** Xcode 16+ is installed with Swift 5.9+
**When** I open the project at `ios/Rial/Rial.xcodeproj`
**Then** the project:
- Builds successfully for iOS 15.0+ targets
- Uses SwiftUI app lifecycle (`@main` entry point)
- Has bundle identifier `app.rial.ios` configured
- Development team configured for device deployment

### AC2: Project Structure
**Given** the Xcode project exists
**When** I examine the folder structure
**Then** it matches the architecture specification:
```
ios/
├── Rial/
│   ├── App/
│   │   ├── RialApp.swift                    # @main entry point
│   │   └── AppDelegate.swift                # Background task handling
│   ├── Core/
│   │   ├── Attestation/                     # DCAppAttest, CaptureAssertion
│   │   ├── Capture/                         # ARCaptureSession, DepthProcessor
│   │   ├── Crypto/                          # CryptoKit wrappers
│   │   ├── Networking/                      # APIClient, UploadService
│   │   └── Storage/                         # CoreData, Keychain
│   ├── Features/
│   │   ├── Capture/                         # CaptureView, ViewModel
│   │   ├── Preview/                         # PreviewView
│   │   ├── History/                         # HistoryView
│   │   └── Result/                          # ResultDetailView
│   ├── Models/                              # Data models
│   ├── Shaders/                             # Metal shaders
│   └── Resources/
│       └── Assets.xcassets
├── RialTests/                               # XCTest unit tests
├── RialUITests/                             # XCUITest UI tests
└── Rial.xcodeproj
```

### AC3: App Capabilities Configuration
**Given** the project is created
**When** I examine Signing & Capabilities in Xcode
**Then** the following are configured:
- **App Attest** capability enabled (for DCAppAttest)
- **Keychain Sharing** capability enabled (for secure storage)
- Background Modes: `background-fetch` enabled (for upload handling)

### AC4: Info.plist Configuration
**Given** the project is created
**When** I examine Info.plist
**Then** it contains:
- `NSCameraUsageDescription`: "Rial uses the camera to capture authenticated photos"
- `NSLocationWhenInUseUsageDescription`: "Rial uses location to verify where photos were taken"
- `NSPhotoLibraryUsageDescription`: "Rial can save verified photos to your library"
- `UIBackgroundModes`: Contains `background-fetch`

### AC5: Test Targets
**Given** the project is created
**When** I examine the project targets
**Then** test targets exist:
- `RialTests` target for XCTest unit tests
- `RialUITests` target for XCUITest UI tests
- Both targets build successfully
- Sample test file exists in each target

### AC6: Git Integration
**Given** the project is created
**When** I check `.gitignore`
**Then** Xcode build artifacts are excluded:
- `*.xcuserdata/`
- `DerivedData/`
- `build/`
- `*.xcworkspace` (we only need xcodeproj)

---

## Tasks

### Task 1: Create Xcode Project
- [x] File > New > Project > iOS App (SwiftUI, Swift)
- [x] Set Product Name: `Rial`
- [x] Set Organization Identifier: `app.rial`
- [x] Set Interface: SwiftUI
- [x] Set Language: Swift
- [x] Uncheck "Core Data" (added manually in Story 6.9)
- [x] Check "Include Tests"
- [x] Save to `ios/` directory in project root

### Task 2: Configure Project Settings
- [x] Set minimum deployment target: iOS 15.0
- [x] Set Swift Language Version: Swift 5.9
- [x] Configure development team in Signing & Capabilities
- [x] Set bundle identifier: `app.rial.ios`
- [x] Set display name: "Rial"

### Task 3: Enable Required Capabilities
- [x] Add "App Attest" capability in Signing & Capabilities
- [x] Add "Keychain Sharing" capability
- [x] Configure keychain access group: `$(AppIdentifierPrefix)app.rial.keychain`
- [x] Add Background Modes capability with `background-fetch`

### Task 4: Create Folder Structure
- [x] Create `App/` group with RialApp.swift, AppDelegate.swift
- [x] Create `Core/Attestation/` group (empty placeholder)
- [x] Create `Core/Capture/` group (empty placeholder)
- [x] Create `Core/Crypto/` group (empty placeholder)
- [x] Create `Core/Networking/` group (empty placeholder)
- [x] Create `Core/Storage/` group (empty placeholder)
- [x] Create `Features/Capture/` group (empty placeholder)
- [x] Create `Features/Preview/` group (empty placeholder)
- [x] Create `Features/History/` group (empty placeholder)
- [x] Create `Features/Result/` group (empty placeholder)
- [x] Create `Models/` group (empty placeholder)
- [x] Create `Shaders/` group (empty placeholder)
- [x] Ensure `Resources/Assets.xcassets` exists

### Task 5: Configure Info.plist
- [x] Add `NSCameraUsageDescription` key with description
- [x] Add `NSLocationWhenInUseUsageDescription` key with description
- [x] Add `NSPhotoLibraryUsageDescription` key with description
- [x] Verify `UIBackgroundModes` array includes `background-fetch`

### Task 6: Create App Entry Point
- [x] Create `RialApp.swift` with `@main` attribute
- [x] Create basic SwiftUI App structure with WindowGroup
- [x] Create placeholder ContentView showing "Rial" text

### Task 7: Create AppDelegate for Background Handling
- [x] Create `AppDelegate.swift`
- [x] Add `@UIApplicationDelegateAdaptor` to RialApp
- [x] Implement `application(_:handleEventsForBackgroundURLSession:completionHandler:)` stub

### Task 8: Update .gitignore
- [x] Add Xcode-specific ignores to root `.gitignore`
- [x] Verify `xcuserdata/`, `DerivedData/`, `build/` are excluded

### Task 9: Verify Test Targets
- [x] Verify RialTests target exists and builds
- [x] Verify RialUITests target exists and builds
- [x] Create sample unit test that passes
- [x] Create sample UI test that passes

### Task 10: Build Verification
- [x] Clean and build project (Cmd+Shift+K, Cmd+B)
- [x] Verify build succeeds for simulator
- [x] Verify build succeeds for device (if available)
- [x] Run tests (Cmd+U) and verify they pass

---

## Technical Implementation Notes

### RialApp.swift
```swift
import SwiftUI

@main
struct RialApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### AppDelegate.swift
```swift
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
```

### ContentView.swift (Placeholder)
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Rial")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Native iOS App")
                .foregroundColor(.secondary)
        }
    }
}
```

### Entitlements Configuration
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.devicecheck.appattest-environment</key>
    <string>development</string>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)app.rial.keychain</string>
    </array>
</dict>
</plist>
```

---

## Dependencies

### Prerequisites
- None (this is the first story in Epic 6)

### Blocks
- **Story 6.2**: DCAppAttest Direct Integration (depends on project structure)
- **Story 6.3**: CryptoKit Integration (depends on Core/Crypto/ folder)
- **Story 6.4**: Keychain Services Integration (depends on Core/Storage/ folder)
- **Story 6.5**: ARKit Unified Capture Session (depends on Core/Capture/ folder)
- **Story 6.9**: CoreData Capture Queue (depends on Core/Storage/ folder)

### External Dependencies
- Xcode 16+ with iOS 18 SDK
- Apple Developer Program membership (for device deployment)
- Physical iPhone Pro (for testing attestation in future stories)

---

## Definition of Done

- [x] All acceptance criteria verified and passing
- [x] All tasks completed
- [x] Project builds successfully for iOS 15.0+ simulator
- [x] Project builds successfully for iOS 15.0+ device (if team configured)
- [x] Unit test target builds and sample test passes
- [x] UI test target builds and sample test passes
- [x] App Attest capability enabled and verified
- [x] Keychain Sharing capability enabled
- [x] Info.plist contains all required usage descriptions
- [x] Folder structure matches architecture specification
- [x] .gitignore updated for Xcode artifacts
- [x] Code committed to feature branch

---

## FR Coverage

| Functional Requirement | Coverage |
|----------------------|----------|
| Infrastructure | Project foundation for all mobile FRs |

This story provides the infrastructure foundation enabling:
- FR1-FR3: Device & Attestation (via App Attest capability)
- FR6-FR13: Capture Flow (via folder structure for Core/Capture/)
- FR14-FR19: Upload & Sync (via background modes and folder structure)
- FR17: Encrypted Storage (via Keychain Sharing capability)

---

## Notes

- Do NOT use the Core Data template during project creation - CoreData will be added manually in Story 6.9 with specific data protection configuration
- The project intentionally has ZERO external dependencies for security reasons
- All security-critical functionality will use Apple's first-party frameworks only
- The folder structure anticipates all 16 stories in Epic 6
- Background modes are required for Story 6.11 (URLSession Background Uploads)

---

## Dev Agent Record

**Implementation Started:** 2025-11-25T05:12:52Z
**Implementation Completed:** 2025-11-25T06:10:00Z
**Implementing Agent:** claude-opus-4-5-20251101 (auto-story-continuous)

### Implementation Notes
- Project structure was partially pre-created; completed remaining items
- Created test files: RialTests.swift, RialUITests.swift, RialUITestsLaunchTests.swift
- Added Assets.xcassets structure with Contents.json, AccentColor.colorset, AppIcon.appiconset
- Verified all capabilities configured in Rial.entitlements (App Attest, Keychain Sharing)
- Info.plist confirmed with all required usage descriptions and background-fetch mode
- .gitignore already correctly configured for ios/ directory

### Deviations from Plan
- None - implementation followed story plan exactly

### Blockers Encountered
- Initial Task tool API errors (500) required direct implementation instead of sub-agent
- iPhone 15 Pro simulator not available; used iPhone 17 Pro instead

### Testing Results
- Build: PASSED (xcodebuild clean build -scheme Rial -destination iPhone 17 Pro)
- Unit Tests: PASSED (2/2 tests - testExample, testPerformanceExample)
- All acceptance criteria verified and passing
