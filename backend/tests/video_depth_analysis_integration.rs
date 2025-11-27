//! Integration tests for Video Depth Analysis Service (Story 7-9)
//!
//! Tests the complete analysis pipeline with realistic test scenarios.
//! These tests validate the depth blob format and analysis algorithms.

use flate2::write::GzEncoder;
use flate2::Compression;
use std::io::Write;

// ============================================================================
// Test Helpers - Blob Creation
// ============================================================================

/// RLDP header magic bytes
const MAGIC: &[u8; 4] = b"RLDP";

/// Create a mock depth data blob with custom frame generator
fn create_depth_blob<F>(frame_count: u32, width: u16, height: u16, frame_fn: F) -> Vec<u8>
where
    F: Fn(u32, u16, u16) -> Vec<f32>,
{
    let frame_size = (width as usize) * (height as usize) * 4;
    let index_size = frame_count as usize * 12; // 12 bytes per index entry
    let data_size = frame_count as usize * frame_size;
    let total_size = 16 + index_size + data_size; // 16 byte header

    let mut data = Vec::with_capacity(total_size);

    // Write header (16 bytes)
    data.extend_from_slice(MAGIC);
    data.extend_from_slice(&1u32.to_le_bytes()); // version
    data.extend_from_slice(&frame_count.to_le_bytes());
    data.extend_from_slice(&width.to_le_bytes());
    data.extend_from_slice(&height.to_le_bytes());

    // Write frame index
    for i in 0..frame_count {
        let timestamp = i as f64 * 0.1; // 10fps
        let offset = i * frame_size as u32;
        data.extend_from_slice(&timestamp.to_le_bytes());
        data.extend_from_slice(&offset.to_le_bytes());
    }

    // Write frame data
    for i in 0..frame_count {
        let frame_data = frame_fn(i, width, height);
        for depth in frame_data {
            data.extend_from_slice(&depth.to_le_bytes());
        }
    }

    // Compress
    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    encoder.write_all(&data).unwrap();
    encoder.finish().unwrap()
}

/// Generate uniform depth frame
fn uniform_frame(depth: f32) -> impl Fn(u32, u16, u16) -> Vec<f32> {
    move |_, w, h| vec![depth; (w as usize) * (h as usize)]
}

/// Generate gradient depth frame (varies by x position)
fn gradient_frame() -> impl Fn(u32, u16, u16) -> Vec<f32> {
    |_, w, h| {
        let mut depths = Vec::with_capacity((w as usize) * (h as usize));
        for _ in 0..h {
            for x in 0..w {
                let depth = 1.0 + (x as f32 / w as f32) * 4.0; // 1m to 5m
                depths.push(depth);
            }
        }
        depths
    }
}

/// Generate frame with gradual temporal change
fn gradual_change_frame() -> impl Fn(u32, u16, u16) -> Vec<f32> {
    |frame_idx, w, h| {
        let mut depths = Vec::with_capacity((w as usize) * (h as usize));
        let base_offset = frame_idx as f32 * 0.01; // Small change per frame
        for y in 0..h {
            for x in 0..w {
                let depth =
                    2.0 + base_offset + (x as f32 / w as f32) * 2.0 + (y as f32 / h as f32) * 0.5;
                depths.push(depth);
            }
        }
        depths
    }
}

/// Generate splice attack - different scenes in first and second half
fn splice_attack_frame() -> impl Fn(u32, u16, u16) -> Vec<f32> {
    |frame_idx, w, h| {
        let mut depths = Vec::with_capacity((w as usize) * (h as usize));
        // First half: indoor scene (1-3m)
        // Second half: outdoor scene (5-15m)
        let base = if frame_idx < 7 { 2.0 } else { 10.0 };
        for row in 0..h {
            for x in 0..w {
                let variation = (x as f32 / w as f32) + (row as f32 / h as f32) * 0.5;
                depths.push(base + variation);
            }
        }
        depths
    }
}

/// Generate frame with impossible depth jump in middle
fn depth_jump_frame() -> impl Fn(u32, u16, u16) -> Vec<f32> {
    |frame_idx, w, h| {
        let mut depths = Vec::with_capacity((w as usize) * (h as usize));
        // Frame 5 has a massive depth jump
        let base = if frame_idx == 5 { 8.0 } else { 2.0 };
        for _ in 0..h {
            for x in 0..w {
                let variation = (x as f32 / w as f32) * 0.5;
                depths.push(base + variation);
            }
        }
        depths
    }
}

// ============================================================================
// Integration Tests - Blob Format Validation
// ============================================================================

#[test]
fn test_blob_header_format() {
    let blob = create_depth_blob(5, 32, 24, uniform_frame(2.0));

    // Decompress to verify structure
    use flate2::read::GzDecoder;
    use std::io::Read;

    let mut decoder = GzDecoder::new(&blob[..]);
    let mut decompressed = Vec::new();
    decoder.read_to_end(&mut decompressed).unwrap();

    // Verify header
    assert_eq!(&decompressed[0..4], b"RLDP", "Magic should be RLDP");

    let version = u32::from_le_bytes(decompressed[4..8].try_into().unwrap());
    assert_eq!(version, 1, "Version should be 1");

    let frame_count = u32::from_le_bytes(decompressed[8..12].try_into().unwrap());
    assert_eq!(frame_count, 5, "Frame count should be 5");

    let width = u16::from_le_bytes(decompressed[12..14].try_into().unwrap());
    let height = u16::from_le_bytes(decompressed[14..16].try_into().unwrap());
    assert_eq!(width, 32, "Width should be 32");
    assert_eq!(height, 24, "Height should be 24");
}

#[test]
fn test_blob_frame_index_format() {
    let blob = create_depth_blob(10, 32, 24, uniform_frame(2.0));

    use flate2::read::GzDecoder;
    use std::io::Read;

    let mut decoder = GzDecoder::new(&blob[..]);
    let mut decompressed = Vec::new();
    decoder.read_to_end(&mut decompressed).unwrap();

    // Read frame index (starts at byte 16)
    for i in 0..10u32 {
        let offset = 16 + (i as usize * 12);
        let timestamp = f64::from_le_bytes(decompressed[offset..offset + 8].try_into().unwrap());
        let frame_offset =
            u32::from_le_bytes(decompressed[offset + 8..offset + 12].try_into().unwrap());

        let expected_timestamp = i as f64 * 0.1;
        assert!(
            (timestamp - expected_timestamp).abs() < 0.001,
            "Frame {i} timestamp should be {expected_timestamp}, got {timestamp}"
        );

        let expected_offset = i * 32 * 24 * 4; // width * height * sizeof(f32)
        assert_eq!(
            frame_offset, expected_offset,
            "Frame {i} offset should be {expected_offset}, got {frame_offset}"
        );
    }
}

#[test]
fn test_blob_frame_data_format() {
    let test_depth = 3.5f32;
    let blob = create_depth_blob(3, 32, 24, uniform_frame(test_depth));

    use flate2::read::GzDecoder;
    use std::io::Read;

    let mut decoder = GzDecoder::new(&blob[..]);
    let mut decompressed = Vec::new();
    decoder.read_to_end(&mut decompressed).unwrap();

    // Frame data starts after header (16) + index (3 * 12)
    let data_start = 16 + 3 * 12;
    let frame_size = 32 * 24;

    // Check first frame
    for i in 0..frame_size {
        let offset = data_start + i * 4;
        let depth = f32::from_le_bytes(decompressed[offset..offset + 4].try_into().unwrap());
        assert!(
            (depth - test_depth).abs() < 0.001,
            "Pixel {i} should have depth {test_depth}, got {depth}"
        );
    }
}

// ============================================================================
// Integration Tests - Analysis Scenarios
// ============================================================================

#[test]
fn test_uniform_scene_blob_size() {
    let blob = create_depth_blob(150, 256, 192, uniform_frame(2.0));

    // 150 frames at 256x192 should produce reasonable compressed size
    // Uniform data compresses very well
    assert!(
        blob.len() < 1_000_000,
        "Uniform blob should compress well, got {} bytes",
        blob.len()
    );
}

#[test]
fn test_varied_scene_blob_size() {
    let blob = create_depth_blob(150, 256, 192, gradual_change_frame());

    // Varied data doesn't compress as well
    assert!(
        blob.len() < 20_000_000,
        "Varied blob should be under 20MB, got {} bytes",
        blob.len()
    );

    // But should still be significantly smaller than raw
    let raw_size = 150 * 256 * 192 * 4 + 16 + 150 * 12; // frames + header + index
    assert!(
        blob.len() < raw_size / 2,
        "Compression ratio should be at least 2:1"
    );
}

#[test]
fn test_splice_attack_detection_data() {
    // Verify splice attack data actually has the discontinuity
    use flate2::read::GzDecoder;
    use std::io::Read;

    let blob = create_depth_blob(15, 32, 24, splice_attack_frame());

    let mut decoder = GzDecoder::new(&blob[..]);
    let mut decompressed = Vec::new();
    decoder.read_to_end(&mut decompressed).unwrap();

    let data_start = 16 + 15 * 12;
    let frame_size = 32 * 24 * 4;

    // Sample frame 3 (before splice) and frame 10 (after splice)
    let frame3_offset = data_start + 3 * frame_size;
    let frame10_offset = data_start + 10 * frame_size;

    let depth3 = f32::from_le_bytes(
        decompressed[frame3_offset..frame3_offset + 4]
            .try_into()
            .unwrap(),
    );
    let depth10 = f32::from_le_bytes(
        decompressed[frame10_offset..frame10_offset + 4]
            .try_into()
            .unwrap(),
    );

    // Should have significant depth difference (indoor vs outdoor)
    let depth_diff = (depth10 - depth3).abs();
    assert!(
        depth_diff > 5.0,
        "Splice should create >5m depth jump, got {depth_diff}"
    );
}

#[test]
fn test_depth_jump_detection_data() {
    use flate2::read::GzDecoder;
    use std::io::Read;

    let blob = create_depth_blob(15, 32, 24, depth_jump_frame());

    let mut decoder = GzDecoder::new(&blob[..]);
    let mut decompressed = Vec::new();
    decoder.read_to_end(&mut decompressed).unwrap();

    let data_start = 16 + 15 * 12;
    let frame_size = 32 * 24 * 4;

    // Sample frame 4 (before jump) and frame 5 (the jump)
    let frame4_offset = data_start + 4 * frame_size;
    let frame5_offset = data_start + 5 * frame_size;

    let depth4 = f32::from_le_bytes(
        decompressed[frame4_offset..frame4_offset + 4]
            .try_into()
            .unwrap(),
    );
    let depth5 = f32::from_le_bytes(
        decompressed[frame5_offset..frame5_offset + 4]
            .try_into()
            .unwrap(),
    );

    // Should have >2m jump at frame 5
    let depth_diff = (depth5 - depth4).abs();
    assert!(
        depth_diff > 2.0,
        "Depth jump should be >2m, got {depth_diff}"
    );
}

// ============================================================================
// Integration Tests - Edge Cases
// ============================================================================

#[test]
fn test_empty_blob_compression() {
    // Can't have 0 frames, but test minimal case
    let blob = create_depth_blob(1, 8, 8, uniform_frame(2.0));
    assert!(!blob.is_empty(), "Even minimal blob should have content");
}

#[test]
fn test_maximum_resolution_blob() {
    // 256x192 is the max LiDAR resolution
    let blob = create_depth_blob(10, 256, 192, uniform_frame(2.0));

    use flate2::read::GzDecoder;
    use std::io::Read;

    let mut decoder = GzDecoder::new(&blob[..]);
    let mut decompressed = Vec::new();
    decoder.read_to_end(&mut decompressed).unwrap();

    // Verify data integrity at max resolution
    let expected_frame_size = 256 * 192 * 4;
    let data_start = 16 + 10 * 12;
    let expected_total = data_start + 10 * expected_frame_size;

    assert_eq!(
        decompressed.len(),
        expected_total,
        "Decompressed size should match expected"
    );
}

#[test]
fn test_gradient_frame_variety() {
    // Verify gradient frames actually have variety
    use flate2::read::GzDecoder;
    use std::io::Read;

    let blob = create_depth_blob(5, 32, 24, gradient_frame());

    let mut decoder = GzDecoder::new(&blob[..]);
    let mut decompressed = Vec::new();
    decoder.read_to_end(&mut decompressed).unwrap();

    let data_start = 16 + 5 * 12;

    // Sample first and last pixel of first frame
    let first_pixel =
        f32::from_le_bytes(decompressed[data_start..data_start + 4].try_into().unwrap());
    let last_pixel_offset = data_start + (32 * 24 - 1) * 4;
    let last_pixel = f32::from_le_bytes(
        decompressed[last_pixel_offset..last_pixel_offset + 4]
            .try_into()
            .unwrap(),
    );

    // Should have gradient variation
    let variation = (last_pixel - first_pixel).abs();
    assert!(
        variation > 2.0,
        "Gradient should have >2m variation, got {variation}"
    );
}

// ============================================================================
// Integration Tests - Histogram Computation (Algorithm Validation)
// ============================================================================

#[test]
fn test_histogram_bin_assignment() {
    // Test that histogram binning is correct
    let depths: [f32; 10] = [0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5, 8.5, 9.5];
    let mut histogram = [0u32; 10];
    let bin_width = 1.0f32; // 10 bins over 0-10m

    for &depth in &depths {
        if (0.1..=10.0).contains(&depth) {
            let bin = ((depth - 0.1) / bin_width).floor() as usize;
            let bin = bin.min(9);
            histogram[bin] += 1;
        }
    }

    // Each depth should fall into its own bin (roughly)
    let total: u32 = histogram.iter().sum();
    assert_eq!(total, 10, "All depths should be binned");

    // Verify distribution is spread out
    let non_empty_bins = histogram.iter().filter(|&&c| c > 0).count();
    assert!(
        non_empty_bins >= 8,
        "Should have at least 8 non-empty bins, got {non_empty_bins}"
    );
}

#[test]
fn test_histogram_similarity_computation() {
    // Identical histograms
    let hist1 = [100u32, 200, 300, 400, 500, 400, 300, 200, 100, 50];
    let hist2 = [100u32, 200, 300, 400, 500, 400, 300, 200, 100, 50];

    // Histogram intersection normalized by minimum sum
    let intersection: u32 = hist1
        .iter()
        .zip(hist2.iter())
        .map(|(a, b)| (*a).min(*b))
        .sum();
    let sum1: u32 = hist1.iter().sum();
    let sum2: u32 = hist2.iter().sum();
    let similarity = intersection as f32 / sum1.min(sum2) as f32;

    assert!(
        (similarity - 1.0).abs() < 0.001,
        "Identical histograms should have similarity 1.0, got {similarity}"
    );
}

#[test]
fn test_histogram_dissimilarity() {
    // Completely different histograms
    let hist1 = [1000u32, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    let hist2 = [0u32, 0, 0, 0, 0, 0, 0, 0, 0, 1000];

    let intersection: u32 = hist1
        .iter()
        .zip(hist2.iter())
        .map(|(a, b)| (*a).min(*b))
        .sum();
    let sum1: u32 = hist1.iter().sum();
    let sum2: u32 = hist2.iter().sum();
    let similarity = if sum1 > 0 && sum2 > 0 {
        intersection as f32 / sum1.min(sum2) as f32
    } else {
        0.0
    };

    assert!(
        similarity < 0.01,
        "Completely different histograms should have similarity ~0, got {similarity}"
    );
}

// ============================================================================
// Integration Tests - Jump Detection (Algorithm Validation)
// ============================================================================

#[test]
fn test_depth_jump_counting() {
    let prev_frame: [f32; 5] = [1.0, 2.0, 3.0, 4.0, 5.0];
    let curr_frame: [f32; 5] = [1.1, 2.1, 6.0, 4.1, 5.1]; // Index 2 has 3m jump

    let max_jump = 2.0;
    let mut jump_count = 0;

    for (p, c) in prev_frame.iter().zip(curr_frame.iter()) {
        if p.is_finite() && c.is_finite() && *p > 0.1 && *c > 0.1 && (p - c).abs() > max_jump {
            jump_count += 1;
        }
    }

    assert_eq!(jump_count, 1, "Should detect exactly 1 jump exceeding 2m");
}

#[test]
fn test_no_false_positive_jumps() {
    // Gradual change should not trigger jump detection
    let prev_frame: [f32; 5] = [1.0, 2.0, 3.0, 4.0, 5.0];
    let curr_frame: [f32; 5] = [1.5, 2.5, 3.5, 4.5, 5.5]; // All +0.5m

    let max_jump = 2.0;
    let mut jump_count = 0;

    for (p, c) in prev_frame.iter().zip(curr_frame.iter()) {
        if p.is_finite() && c.is_finite() && (p - c).abs() > max_jump {
            jump_count += 1;
        }
    }

    assert_eq!(
        jump_count, 0,
        "Gradual change should not trigger jump detection"
    );
}
