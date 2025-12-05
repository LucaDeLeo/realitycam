//
//  DepthVisualization.metal
//  Rial
//
//  Created by RealityCam on 2025-11-25.
//
//  Metal shaders for real-time LiDAR depth visualization.
//  Renders depth data as a color gradient overlaid on camera preview.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Vertex Output Structure

/// Vertex shader output for full-screen quad rendering.
struct VertexOut {
    /// Clip-space position
    float4 position [[position]];
    /// Texture coordinates for depth sampling
    float2 texCoord;
};

// MARK: - Color Constants

/// Near color (red) for close objects
constant float3 nearColor = float3(1.0, 0.0, 0.0);

/// Far color (blue) for distant objects
constant float3 farColor = float3(0.0, 0.0, 1.0);

// MARK: - Vertex Shader

/// Vertex shader for full-screen quad rendering.
///
/// Converts vertex positions from clip space (-1 to 1) to texture coordinates (0 to 1).
///
/// - Parameters:
///   - vertexID: Current vertex index (0-5 for 2 triangles)
///   - positions: Vertex positions in clip space
/// - Returns: Vertex output with position and texture coordinates
vertex VertexOut depthVertex(
    uint vertexID [[vertex_id]],
    constant float2 *positions [[buffer(0)]]
) {
    VertexOut out;
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

// MARK: - Fragment Shader

/// Fragment shader for depth-to-color mapping.
///
/// Samples the depth texture and converts depth values (in meters) to a color gradient.
/// Near objects appear red, far objects appear blue.
///
/// - Parameters:
///   - in: Interpolated vertex output
///   - depthTex: Depth texture (r32Float format, values in meters)
///   - nearPlane: Minimum depth for normalization (default: 0.5m)
///   - farPlane: Maximum depth for normalization (default: 5.0m)
///   - opacity: Alpha channel value for overlay blending (0.0-1.0)
/// - Returns: RGBA color for the fragment
fragment float4 depthFragment(
    VertexOut in [[stage_in]],
    texture2d<float> depthTex [[texture(0)]],
    constant float &nearPlane [[buffer(0)]],
    constant float &farPlane [[buffer(1)]],
    constant float &opacity [[buffer(2)]]
) {
    // Sample depth texture using bilinear filtering
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float depth = depthTex.sample(s, in.texCoord).r;

    // Handle invalid depth values (NaN, Inf, or zero)
    if (isinf(depth) || isnan(depth) || depth <= 0.0) {
        return float4(0.0, 0.0, 0.0, 0.0);  // Transparent
    }

    // Normalize depth to 0-1 range
    // saturate() clamps to 0-1 range
    float normalized = saturate((depth - nearPlane) / (farPlane - nearPlane));

    // Interpolate between near and far colors
    float3 color = mix(nearColor, farColor, normalized);

    return float4(color, opacity);
}

// MARK: - Alternative Multi-Color Gradient

/// Alternative fragment shader with rainbow color gradient.
///
/// Provides more colorful visualization with distinct color bands:
/// - Red (0-20%): Very close (0.5-1.4m)
/// - Orange/Yellow (20-40%): Close (1.4-2.3m)
/// - Green (40-60%): Medium (2.3-3.2m)
/// - Cyan (60-80%): Far (3.2-4.1m)
/// - Blue (80-100%): Very far (4.1-5.0m)
fragment float4 depthFragmentRainbow(
    VertexOut in [[stage_in]],
    texture2d<float> depthTex [[texture(0)]],
    constant float &nearPlane [[buffer(0)]],
    constant float &farPlane [[buffer(1)]],
    constant float &opacity [[buffer(2)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float depth = depthTex.sample(s, in.texCoord).r;

    if (isinf(depth) || isnan(depth) || depth <= 0.0) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }

    float normalized = saturate((depth - nearPlane) / (farPlane - nearPlane));

    // HSV-like color mapping (hue from 0 to 240 degrees, red to blue)
    float hue = normalized * 0.667;  // 0 to 2/3 (red to blue in HSV)

    float3 color;
    if (hue < 0.167) {  // Red to Yellow
        color = float3(1.0, hue * 6.0, 0.0);
    } else if (hue < 0.333) {  // Yellow to Green
        color = float3(1.0 - (hue - 0.167) * 6.0, 1.0, 0.0);
    } else if (hue < 0.5) {  // Green to Cyan
        color = float3(0.0, 1.0, (hue - 0.333) * 6.0);
    } else if (hue < 0.667) {  // Cyan to Blue
        color = float3(0.0, 1.0 - (hue - 0.5) * 6.0, 1.0);
    } else {  // Blue
        color = float3(0.0, 0.0, 1.0);
    }

    return float4(color, opacity);
}
