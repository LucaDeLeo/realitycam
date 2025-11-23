# Story Context: 4-5 LiDAR Depth Analysis Service

## Story Reference
- **Story ID**: 4-5
- **Title**: LiDAR Depth Analysis Service
- **Status**: ready-for-dev
- **Epic**: 4 - Upload, Processing & Evidence Generation

## Acceptance Criteria Summary

| AC | Description | Threshold/Requirement |
|----|-------------|----------------------|
| AC-1 | Depth Map Decompression | gzip decompress, parse Float32 LE, validate 256x192 |
| AC-2 | Statistical Analysis | variance (std dev), min/max depth, coverage % |
| AC-3 | Depth Layer Detection | histogram peaks, >= 3 layers = real scene |
| AC-4 | Edge Coherence | depth gradient analysis, 0.0-1.0 score |
| AC-5 | Real Scene Determination | variance > 0.5 AND layers >= 3 AND coherence > 0.7 |
| AC-6 | Evidence Integration | Store in DepthAnalysis struct, update confidence |
| AC-7 | Performance | < 2 seconds total |
| AC-8 | Error Handling | Non-blocking, status = unavailable on failure |

## Key Thresholds

```
is_likely_real_scene = true when ALL:
  - depth_variance > 0.5  (std dev in meters)
  - depth_layers >= 3     (distinct histogram peaks)
  - edge_coherence > 0.7  (0.0-1.0 correlation)
```

## Existing Types (AUTHORITATIVE)

### DepthAnalysis Struct (backend/src/models/evidence.rs)

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DepthAnalysis {
    pub status: CheckStatus,        // pass/fail/unavailable
    pub depth_variance: f64,        // std dev in meters
    pub depth_layers: u32,          // distinct depth planes
    pub edge_coherence: f64,        // 0.0-1.0
    pub min_depth: f64,             // meters
    pub max_depth: f64,             // meters
    pub is_likely_real_scene: bool,
}

impl Default for DepthAnalysis {
    fn default() -> Self {
        Self {
            status: CheckStatus::Unavailable,
            depth_variance: 0.0,
            depth_layers: 0,
            edge_coherence: 0.0,
            min_depth: 0.0,
            max_depth: 0.0,
            is_likely_real_scene: false,
        }
    }
}
```

### CheckStatus Enum (backend/src/models/evidence.rs)

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CheckStatus {
    Pass,
    Fail,
    Unavailable,
}
```

## S3 Integration Points

### StorageService (backend/src/services/storage.rs)

```rust
// Existing key generation
pub fn depth_map_s3_key(capture_id: Uuid) -> String {
    format!("captures/{capture_id}/depth.gz")
}

// Need to ADD: download method
pub async fn download_depth_map(&self, capture_id: Uuid) -> Result<Vec<u8>, ApiError>
```

## Upload Handler Integration (backend/src/routes/captures.rs)

### Current Code (Line 438-440)
```rust
let evidence_package = EvidencePackage {
    hardware_attestation,
    depth_analysis: DepthAnalysis::default(),  // <-- REPLACE THIS
    metadata: MetadataEvidence { ... },
};
```

### Target Integration
```rust
// After S3 upload, before evidence package assembly
let depth_analysis = match analyze_depth_map(&storage, capture_id, &parsed.metadata).await {
    Ok(analysis) => analysis,
    Err(e) => {
        tracing::warn!(
            capture_id = %capture_id,
            error = %e,
            "[depth_analysis] Analysis failed, continuing with unavailable"
        );
        DepthAnalysis::default()
    }
};
```

## Depth Map Format

- **Compression**: gzip
- **Data Type**: Float32 array (little-endian)
- **Dimensions**: 256x192 (typical iPhone Pro LiDAR)
- **Units**: Meters
- **Invalid Values**: 0.0, NaN, inf (exclude from analysis)
- **Compressed Size**: ~1MB
- **Uncompressed Size**: 256 * 192 * 4 = 196,608 bytes

## Algorithm Specifications

### 1. Variance Calculation
```rust
fn compute_variance(depths: &[f32]) -> f64 {
    let valid: Vec<f64> = depths.iter()
        .filter(|d| d.is_finite() && **d > 0.0)
        .map(|d| *d as f64)
        .collect();

    let mean = valid.iter().sum::<f64>() / valid.len() as f64;
    let variance = valid.iter().map(|d| (d - mean).powi(2)).sum::<f64>() / valid.len() as f64;
    variance.sqrt() // Return std dev
}
```

### 2. Depth Layer Detection (Histogram-based)
```rust
fn count_depth_layers(depths: &[f32], min: f32, max: f32) -> u32 {
    // 1. Create histogram with 50-100 bins over depth range
    // 2. Smooth histogram to reduce noise
    // 3. Find peaks with prominence > threshold
    // 4. Count significant peaks
}
```

### 3. Edge Coherence (Depth-only for MVP)
```rust
fn compute_edge_coherence(depths: &[f32], width: usize, height: usize) -> f64 {
    // 1. Compute depth gradient magnitude (Sobel)
    // 2. Threshold to find depth edges
    // 3. Compute edge density as scene complexity proxy
    // Note: Full photo comparison deferred to post-MVP
}
```

## Dependencies to Add (Cargo.toml)

```toml
flate2 = "1.0"       # gzip decompression
byteorder = "1.5"    # Float32 little-endian parsing
```

## File Structure

```
backend/src/services/
├── mod.rs                    # Add: pub mod depth_analysis
├── depth_analysis.rs         # NEW: Main analysis module
├── storage.rs                # ADD: download_depth_map method
└── ...existing...
```

## Error Handling Matrix

| Error | Action | Evidence Status |
|-------|--------|-----------------|
| S3 download failed | Log WARN, continue | unavailable |
| Gzip decompression failed | Log WARN, continue | unavailable |
| Invalid float data | Log WARN, continue | unavailable |
| Dimension mismatch | Log WARN, use actual | Continue |
| All depths invalid | Log WARN | unavailable |
| Analysis OK, flat scene | Log INFO | fail |
| Analysis OK, real scene | Log INFO | pass |

## Performance Budget

- S3 download: ~200ms
- Gzip decompress: ~10ms
- Float32 parsing: ~1ms
- Variance calc: ~5ms
- Layer detection: ~20ms
- Edge coherence: ~50ms
- **Total**: ~300ms (well within 2s budget)

## Test Scenarios

| Scenario | Expected Outcome |
|----------|------------------|
| Flat plane (all ~0.4m) | layers=1, variance<0.1, is_real=false |
| Two planes (0.4m, 2.0m) | layers=2, moderate variance, is_real=false |
| Real scene (0.5m-5.0m) | layers>=3, variance>0.5, is_real=true |
| Invalid data (NaN/inf) | Gracefully handle, exclude from stats |
| Empty depth map | status=unavailable |

## Logging Patterns

```rust
tracing::info!(
    capture_id = %capture_id,
    depth_variance = variance,
    depth_layers = layers,
    edge_coherence = coherence,
    is_likely_real_scene = is_real,
    "[depth_analysis] Analysis complete"
);

tracing::warn!(
    capture_id = %capture_id,
    error = %e,
    "[depth_analysis] Failed to decompress depth map"
);
```

## Integration Checklist

1. [ ] Add `flate2` and `byteorder` to Cargo.toml
2. [ ] Create `backend/src/services/depth_analysis.rs`
3. [ ] Add `download_depth_map` to StorageService
4. [ ] Export module in `backend/src/services/mod.rs`
5. [ ] Integrate in `backend/src/routes/captures.rs`
6. [ ] Replace `DepthAnalysis::default()` with real analysis
7. [ ] Handle errors gracefully (non-blocking)
8. [ ] Add unit tests with synthetic data
9. [ ] Verify cargo check and cargo test pass
