# Strategic Sketch: rial. Android & Multi-Signal Detection

**Date:** 2025-12-11
**Author:** John (PM Agent) + Luca
**Status:** DRAFT - Strategic Sketch (REVISED with assumption testing)
**Based On:** Technical Research (research-technical-2025-12-11.md)

---

## Executive Summary

This document outlines the strategic architecture for:
1. **Expanding rial. to Android** with multi-signal flat media detection
2. **Enhancing iOS** to include all parallel verification methods (defense in depth)

The unified architecture enables:
- Android devices to achieve **MEDIUM-HIGH** confidence without LiDAR (revised from HIGH)
- iOS Pro devices to become even stronger (LiDAR + all secondary methods)
- Future expansion to non-Pro iPhones via parallax-based detection
- Transparent verification showing HOW confidence was calculated

> ⚠️ **Key Revision:** After assumption testing, this sketch adopts an **attestation-first trust model**. Hardware attestation is the PRIMARY trust signal; detection algorithms are SUPPORTING evidence (vulnerable to Chimera-style attacks).

---

## ⚠️ Critical Security Findings

Based on assumption testing in [Technical Research](./research-technical-2025-12-11.md#addendum-strategic-sketch-assumption-testing):

| Finding | Impact | Mitigation |
|---------|--------|------------|
| **Chimera Attack (USENIX Security 2025)** | Bypasses Moiré + deepfake detection | Attestation-first trust model |
| **RenderScript Deprecated** | Cannot use for Android FFT | Use Vulkan Compute or CPU-based FFT |
| **Play Integrity Bypass** | Android attestation weaker than iOS | Multi-layer backend validation |
| **Parallax Limitations** | Flat surface at unknown distance harder | Reduce claim to MEDIUM-HIGH |

### Trust Model Adjustment

**Original assumption:** Detection methods provide primary confidence.

**Revised model:** **Attestation-first trust** — hardware attestation is PRIMARY, detection methods are SUPPORTING evidence.

```
Trust Hierarchy:
1. Hardware Attestation (LiDAR, TEE/StrongBox) → PRIMARY
2. Physical Signals (Parallax, Depth) → STRONG SUPPORTING
3. Detection Algorithms (Moiré, Texture) → SUPPORTING (vulnerable to adversarial attack)
```

---

## Strategic Decisions

| # | Decision Area | Choice | Rationale |
|---|---------------|--------|-----------|
| 1 | Product Identity | **rial. for Android** | Unified brand, same trust model |
| 2 | Confidence Display | **Show method breakdown** | Transparency on how verification works |
| 3 | Detection Stack | **Multi-signal fusion** | Parallax + Moiré + Texture + Artifacts |
| 4 | iOS Enhancement | **Add all parallel methods** | Defense in depth, harder to spoof |
| 5 | Hardware Attestation | **TEE minimum** | ~90% Android coverage, reject software-only |
| 6 | Architecture | **Native Kotlin** | Mirrors iOS Swift decision, security-first |
| 7 | Detection Location | **Client-side** | Privacy-preserving, server verifies attestation |
| 8 | Evidence Model | **Unified with breakdown** | Same schema for iOS and Android |

---

## Detection Architecture

### Multi-Signal Stack

```
┌─────────────────────────────────────────────────────────────────┐
│                    DETECTION CAPABILITIES                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Method              │ iOS (Pro)  │ iOS (non-Pro) │ Android        │
│  ────────────────────┼────────────┼───────────────┼────────────────│
│  LiDAR Depth         │ ✅ PRIMARY │ ❌            │ ❌             │
│  Multi-Cam Parallax  │ ⚡ BONUS   │ ✅ PRIMARY    │ ✅ PRIMARY     │
│  Moiré FFT           │ ✅         │ ✅            │ ✅             │
│  Texture CNN         │ ✅         │ ✅            │ ✅             │
│  Artifact Detection  │ ✅         │ ✅            │ ✅             │
│  ────────────────────┼────────────┼───────────────┼────────────────│
│  Max Confidence      │ VERY HIGH  │ HIGH          │ MEDIUM-HIGH ⚠️ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Detection Methods

#### Tier 1: Primary Depth Signal
- **iOS Pro:** LiDAR (direct depth measurement via ARKit)
- **Android/iOS Standard:** Multi-camera parallax (disparity-based depth)

#### Tier 2: Universal Detection (Always Available)
- **Moiré Pattern Detection:** 2D FFT frequency analysis detects screen pixel grid interference
- **Texture Classification:** MobileNetV3 CNN distinguishes real-world vs screen/print materials

#### Tier 3: Supporting Signals
- PWM/refresh rate artifacts
- Specular reflection patterns
- Halftone detection (prints)
- Defocus uniformity analysis

### Confidence Weighting

> ⚠️ **REVISED** based on Chimera attack vulnerability and attestation trust model findings.

```swift
// iOS Pro: LiDAR is primary, others reinforce
// REVISED: Increased LiDAR weight, decreased Moiré (Chimera vulnerability)
let iOSProWeights = [
    "lidar": 0.55,        // ↑ from 0.50 - most reliable physical signal
    "moire": 0.15,        // ↓ from 0.20 - Chimera attack vulnerability
    "texture": 0.15,      // unchanged
    "supporting": 0.15    // unchanged
]

// Android: Multi-signal fusion with attestation weighting
// REVISED: Added attestation_level, reduced moiré weight
let androidWeights = [
    "attestation_level": 0.20,  // NEW - StrongBox > TEE > Software
    "parallax": 0.30,           // ↓ from 0.35 - flat surface concerns
    "moire": 0.15,              // ↓ from 0.25 - Chimera vulnerability
    "texture": 0.20,            // ↓ from 0.25
    "supporting": 0.15          // unchanged
]
```

**Rationale for changes:**
- Hardware signals (LiDAR, attestation level) weighted higher — more resilient to adversarial attacks
- Moiré reduced — vulnerable to Chimera-style bypass attacks
- Android includes explicit attestation level weighting since TEE vs StrongBox matters

---

## Hardware Attestation

> ⚠️ **Security Note:** Android attestation is **WEAKER** than iOS DCAppAttest. Play Integrity bypass modules exist (PlayIntegrityFork, Kitsune Mask). Do NOT treat Android attestation as equivalent to iOS. See [Technical Research](./research-technical-2025-12-11.md#assumption-6-android-attestation--ios-dcappattest).

### Android Attestation Tiers

| Tier | Trust Level | Coverage | Action |
|------|-------------|----------|--------|
| StrongBox | HIGH | ~30-40% | Full support |
| TEE | MEDIUM | ~90% | **Minimum requirement** |
| Software | REJECTED | 100% | **Rejected** |

### Evidence Impact (Revised)

| Attestation Level | Detection Required | Max Confidence |
|-------------------|-------------------|----------------|
| StrongBox | Parallax OR Moiré | **MEDIUM-HIGH** |
| TEE | Parallax AND Moiré AND Texture | **MEDIUM** |
| Software | N/A | **REJECTED** |

### Backend Validation Requirements

Given Play Integrity bypass risk, backend MUST implement:

1. **Attestation certificate chain validation** — verify full chain to Google root
2. **Challenge freshness** — time-bound nonces to prevent replay
3. **Device property consistency** — cross-validate device model, OS version, patch level
4. **Anomaly detection** — flag devices with unusual attestation patterns

---

## Architecture

### Unified Detection Core

```
┌─────────────────────────────────────────────────────────────────┐
│            SHARED DETECTION CORE (Pure Algorithms)               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Platform-Specific Layer:                                        │
│  ┌─────────────────────┐    ┌─────────────────────┐             │
│  │       iOS           │    │      Android        │             │
│  │  ├── ARKit+LiDAR    │    │  ├── Camera2 API    │             │
│  │  └── DCAppAttest    │    │  └── Key Attestation│             │
│  └─────────────────────┘    └─────────────────────┘             │
│              │                        │                          │
│              ▼                        ▼                          │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Shared Detection Algorithms                 │    │
│  │  ├── MoireDetector (FFT frequency analysis)             │    │
│  │  ├── TextureClassifier (CoreML/TFLite)                  │    │
│  │  ├── ArtifactDetector (PWM, specular, halftone)         │    │
│  │  └── ConfidenceAggregator + CrossValidator              │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### iOS Project Structure (New Detection Module)

```
ios/Rial/Core/
├── Detection/                    # NEW MODULE
│   ├── MoireDetector.swift       # Accelerate 2D FFT
│   ├── TextureClassifier.swift   # CoreML inference
│   ├── ArtifactDetector.swift    # PWM, specular, halftone
│   ├── ConfidenceAggregator.swift
│   └── CrossValidator.swift
```

### Android Project Structure

```
android/
├── app/src/main/java/com/rial/
│   ├── RialApplication.kt
│   ├── core/
│   │   ├── attestation/
│   │   │   └── KeyAttestationService.kt
│   │   ├── capture/
│   │   │   ├── MultiCameraSession.kt
│   │   │   └── ParallaxAnalyzer.kt
│   │   ├── detection/
│   │   │   ├── MoireDetector.kt
│   │   │   ├── TextureClassifier.kt
│   │   │   └── ConfidenceAggregator.kt
│   │   ├── crypto/
│   │   │   └── SecureKeyStore.kt
│   │   └── networking/
│   │       └── ApiClient.kt
│   └── ui/
│       ├── capture/
│       ├── preview/
│       └── history/
```

---

## Evidence Model (Unified)

```json
{
  "platform": "ios" | "android",
  "confidence_level": "HIGH",
  "confidence_score": 0.91,

  "hardware_attestation": {
    "status": "pass",
    "method": "secure_enclave" | "strongbox" | "tee",
    "device_model": "iPhone 15 Pro"
  },

  "scene_analysis": {
    "status": "pass",
    "is_likely_real_scene": true,
    "primary_method": "lidar",
    "method_suite": "lidar_plus_multi_signal",

    "breakdown": {
      "lidar": {
        "available": true,
        "depth_variance": 2.4,
        "depth_layers": 5,
        "edge_coherence": 0.87,
        "score": 0.95,
        "weight": 0.50
      },
      "parallax": {
        "available": false,
        "reason": "lidar_preferred",
        "score": null,
        "weight": 0.00
      },
      "moire": {
        "available": true,
        "screen_detected": false,
        "frequency_peaks": [],
        "score": 0.88,
        "weight": 0.20
      },
      "texture": {
        "available": true,
        "classification": "real_scene",
        "material_confidence": 0.82,
        "score": 0.82,
        "weight": 0.15
      },
      "supporting": {
        "pwm_detected": false,
        "specular_uniformity": 0.15,
        "halftone_detected": false,
        "score": 0.79,
        "weight": 0.15
      }
    },

    "cross_validation": {
      "methods_agree": true,
      "disagreement_score": 0.05,
      "flagged": false
    },

    "final_score": 0.91
  }
}
```

---

## Implementation Roadmap

### Phase 1: iOS Multi-Signal Foundation

**Objective:** Add moiré, texture, and artifact detection to iOS

| Story | Description |
|-------|-------------|
| 1.1 | Moiré Detection Module (Accelerate FFT) |
| 1.2 | Texture Classification (CoreML MobileNetV3) |
| 1.3 | Artifact Detection Suite |
| 1.4 | Confidence Aggregator + Cross-Validation |
| 1.5 | Integration with existing capture flow |

**Deliverable:** iOS with LiDAR + all secondary methods

### Phase 2: Backend & Evidence Model

**Objective:** Support both platforms with unified evidence

| Story | Description |
|-------|-------------|
| 2.1 | Expanded evidence schema (breakdown storage) |
| 2.2 | Android Key Attestation service |
| 2.3 | Unified capture endpoint (iOS + Android) |
| 2.4 | Migration + backward compatibility |

**Deliverable:** Backend accepts both platforms

### Phase 3: Verification UI

**Objective:** Show method breakdown to users

| Story | Description |
|-------|-------------|
| 3.1 | Detection method visualization (bars/scores) |
| 3.2 | Cross-validation display |
| 3.3 | Platform indicator |

**Deliverable:** Verification shows HOW confidence was achieved

### Phase 4: Android App

**Objective:** Full Android app with feature parity

| Story | Description |
|-------|-------------|
| 4.1 | Project setup (Kotlin + Jetpack Compose) |
| 4.2 | Key Attestation integration |
| 4.3 | Multi-camera parallax capture |
| 4.4 | Detection module (port from iOS) |
| 4.5 | Upload + offline queue |
| 4.6 | Jetpack Compose UI |
| 4.7 | Feature parity validation |

**Deliverable:** Full Android app

### Dependency Graph

```
Phase 1 (iOS Multi-Signal)
         │
         ├─────────────┐
         ▼             ▼
Phase 2 (Backend) → Phase 3 (UI)
         │
         ▼
Phase 4 (Android)
```

---

## Epic Structure (Proposed)

```
Epic 9: iOS Multi-Signal Detection Enhancement
Epic 10: Backend Platform Expansion
Epic 11: Verification UI - Method Breakdown
Epic 12: Android Native App
```

---

## Risk Mitigation

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Chimera-style attacks** | HIGH | Attestation-first trust model; detection is SUPPORTING not PRIMARY |
| **Play Integrity bypass** | HIGH | Multi-layer backend validation; don't trust client scores blindly |
| **RenderScript deprecation** | MEDIUM | Use Vulkan Compute or CPU-based FFT |
| **Parallax flat-surface limitation** | MEDIUM | Require scene complexity; combine with multiple signals |
| ML model accuracy | MEDIUM | Start with Moiré (deterministic FFT) before CNN |
| Android camera fragmentation | MEDIUM | Target Pixel + Samsung flagships first |
| Training data collection | LOW | Controlled test rig (screen + real scenes) |
| Performance on low-end Android | LOW | TFLite GPU delegate, CPU fallback |
| Algorithm drift between platforms | LOW | Shared test dataset, cross-platform validation |

### New Monitoring Requirements

| Item | Action |
|------|--------|
| Chimera attack evolution | Monitor USENIX Security / academic research |
| Play Integrity bypass state | Track XDA forums, update server validation |
| TEE/StrongBox adoption | Collect device telemetry post-launch |

---

## Performance Targets

| Method | iOS Time | Android Time | Notes |
|--------|----------|--------------|-------|
| LiDAR Analysis | ~50ms | N/A | Existing |
| Parallax | N/A | ~100ms | Stereo matching |
| Moiré FFT | ~30ms | ~40ms | Accelerate / **Vulkan Compute** ⚠️ |
| Texture CNN | ~15ms | ~20ms | CoreML / TFLite |
| Artifacts | ~20ms | ~25ms | Pure computation |
| **Total (parallel)** | **~50ms** | **~100ms** | All run concurrently |

> ⚠️ **Note:** RenderScript is deprecated (Android 12+). Use Vulkan Compute or CPU-based FFT for Android.

---

## Next Steps

1. **Review & Approve** this strategic sketch (including security findings)
2. **Formalize into PRD expansion** (modify existing PRD)
3. **Create ADR-012** for attestation-first trust model + multi-signal detection
4. **Create Epics 9-12** with detailed stories
5. **Architecture update** (incorporate backend validation requirements)
6. **Begin Phase 1** implementation (iOS multi-signal)

---

## References

- [Technical Research: Screen Recapture Detection](./research-technical-2025-12-11.md)
- [Technical Research: Assumption Testing Addendum](./research-technical-2025-12-11.md#addendum-strategic-sketch-assumption-testing)
- [Current PRD](./prd.md)
- [Current Architecture](./architecture.md)
- [ADR-009: Native Swift Architecture](./architecture.md#adr-009)

### Security Research (Critical Reading)

- [Chimera: Creating Digitally Signed Fake Photos](https://www.usenix.org/conference/usenixsecurity25/presentation/park) — USENIX Security 2025
- [Play Integrity Bypass Guide](https://xdaforums.com/t/guide-bypass-play-integrity-device-strong-using-kitsune-mask-august-2025.4753374/) — XDA Forums 2025
- [Android GPU Compute Going Forward](https://android-developers.googleblog.com/2021/04/android-gpu-compute-going-forward.html) — RenderScript deprecation

---

*Generated via BMAD Correct Course Workflow*
*Date: 2025-12-11*
*PM Agent: John*
