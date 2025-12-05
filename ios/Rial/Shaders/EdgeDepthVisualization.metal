//
//  EdgeDepthVisualization.metal
//  Rial
//
//  Created by RealityCam on 2025-11-26.
//
//  Metal shaders for real-time Sobel edge detection on LiDAR depth data.
//  Renders depth discontinuities as colored edges (cyan=near, magenta=far)
//  for video recording preview without obscuring the camera view.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Vertex Output Structure

/// Vertex shader output for full-screen quad rendering.
/// Shared structure with DepthVisualization.metal.
struct EdgeVertexOut {
    /// Clip-space position
    float4 position [[position]];
    /// Texture coordinates for depth sampling
    float2 texCoord;
};

// MARK: - Edge Color Constants

/// Near edge color (cyan) for close objects
constant float3 nearEdgeColor = float3(0.0, 1.0, 1.0);

/// Far edge color (magenta) for distant objects
constant float3 farEdgeColor = float3(1.0, 0.0, 1.0);

/// Edge alpha when above threshold
constant float edgeAlpha = 0.8;

// MARK: - Vertex Shader

/// Vertex shader for full-screen quad rendering.
///
/// Converts vertex positions from clip space (-1 to 1) to texture coordinates (0 to 1).
///
/// - Parameters:
///   - vertexID: Current vertex index (0-5 for 2 triangles)
///   - positions: Vertex positions in clip space
/// - Returns: Vertex output with position and texture coordinates
vertex EdgeVertexOut edgeDepthVertex(
    uint vertexID [[vertex_id]],
    constant float2 *positions [[buffer(0)]]
) {
    EdgeVertexOut out;
    float2 pos = positions[vertexID];
    out.position = float4(pos, 0.0, 1.0);

    // Convert clip space (-1...1) to texture coordinates (0...1)
    out.texCoord = (pos + 1.0) * 0.5;

    // Flip Y for texture coordinates (Metal texture origin is top-left)
    out.texCoord.y = 1.0 - out.texCoord.y;

    // Rotate 90° CW for portrait orientation
    // ARKit depth maps are in landscape (sensor native), need rotation for portrait display
    out.texCoord = float2(out.texCoord.y, 1.0 - out.texCoord.x);

    return out;
}

// MARK: - Sobel Edge Detection Fragment Shader

/// Fragment shader for Sobel edge detection on depth buffer.
///
/// Applies Sobel operator to detect depth discontinuities (edges).
/// Only edge pixels are rendered, producing a sparse visualization
/// that doesn't obscure the camera preview.
///
/// Sobel operators:
/// ```
/// Gx kernel:    Gy kernel:
/// [-1  0  1]    [-1 -2 -1]
/// [-2  0  2]    [ 0  0  0]
/// [-1  0  1]    [ 1  2  1]
///
/// edge = sqrt(Gx^2 + Gy^2)
/// ```
///
/// - Parameters:
///   - in: Interpolated vertex output
///   - depthTexture: Depth texture (r32Float format, values in meters)
///   - nearPlane: Minimum depth for color normalization (default: 0.5m)
///   - farPlane: Maximum depth for color normalization (default: 5.0m)
///   - edgeThreshold: Minimum edge magnitude to render (default: 0.1)
/// - Returns: RGBA color for the fragment (transparent if not an edge)
fragment float4 edgeDepthFragment(
    EdgeVertexOut in [[stage_in]],
    texture2d<float> depthTexture [[texture(0)]],
    constant float &nearPlane [[buffer(0)]],
    constant float &farPlane [[buffer(1)]],
    constant float &edgeThreshold [[buffer(2)]]
) {
    // Create sampler with bilinear filtering
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    // Calculate texel size for neighbor sampling
    float2 texelSize = 1.0 / float2(depthTexture.get_width(), depthTexture.get_height());

    // Sample 3x3 neighborhood for Sobel operator
    // tl=top-left, tm=top-middle, tr=top-right
    // ml=middle-left, mr=middle-right
    // bl=bottom-left, bm=bottom-middle, br=bottom-right
    float tl = depthTexture.sample(s, in.texCoord + float2(-1, -1) * texelSize).r;
    float tm = depthTexture.sample(s, in.texCoord + float2( 0, -1) * texelSize).r;
    float tr = depthTexture.sample(s, in.texCoord + float2( 1, -1) * texelSize).r;
    float ml = depthTexture.sample(s, in.texCoord + float2(-1,  0) * texelSize).r;
    float mr = depthTexture.sample(s, in.texCoord + float2( 1,  0) * texelSize).r;
    float bl = depthTexture.sample(s, in.texCoord + float2(-1,  1) * texelSize).r;
    float bm = depthTexture.sample(s, in.texCoord + float2( 0,  1) * texelSize).r;
    float br = depthTexture.sample(s, in.texCoord + float2( 1,  1) * texelSize).r;

    // Sample center pixel for depth-based coloring
    float center = depthTexture.sample(s, in.texCoord).r;

    // Handle invalid depth values (NaN, Inf, or non-positive)
    // Return transparent for invalid center depth
    if (isinf(center) || isnan(center) || center <= 0.0) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }

    // Replace invalid neighbor values with center to avoid edge artifacts
    // This ensures we don't detect "edges" at invalid depth boundaries
    if (isinf(tl) || isnan(tl) || tl <= 0.0) tl = center;
    if (isinf(tm) || isnan(tm) || tm <= 0.0) tm = center;
    if (isinf(tr) || isnan(tr) || tr <= 0.0) tr = center;
    if (isinf(ml) || isnan(ml) || ml <= 0.0) ml = center;
    if (isinf(mr) || isnan(mr) || mr <= 0.0) mr = center;
    if (isinf(bl) || isnan(bl) || bl <= 0.0) bl = center;
    if (isinf(bm) || isnan(bm) || bm <= 0.0) bm = center;
    if (isinf(br) || isnan(br) || br <= 0.0) br = center;

    // Apply Sobel operators for horizontal and vertical gradients
    // Gx detects vertical edges, Gy detects horizontal edges
    float gx = (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl);
    float gy = (bl + 2.0 * bm + br) - (tl + 2.0 * tm + tr);

    // Compute edge magnitude
    float edge = sqrt(gx * gx + gy * gy);

    // Early exit for non-edge pixels (below threshold)
    // This provides performance optimization by skipping color computation
    if (edge <= edgeThreshold) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }

    // Normalize center depth for color interpolation
    // saturate() clamps to 0-1 range
    float normalizedDepth = saturate((center - nearPlane) / (farPlane - nearPlane));

    // Interpolate between near (cyan) and far (magenta) colors based on depth
    float3 edgeColor = mix(nearEdgeColor, farEdgeColor, normalizedDepth);

    return float4(edgeColor, edgeAlpha);
}
