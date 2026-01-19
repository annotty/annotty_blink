#include <metal_stdlib>
#include "ShaderTypes.h"

using namespace metal;

// MARK: - Vertex Shader

struct FragmentIn {
    float4 position [[position]];
    float2 texCoord;
};

/// Full-screen triangle vertex shader for canvas rendering
vertex FragmentIn canvasVertex(uint vertexID [[vertex_id]],
                                constant ImageUniforms &uniforms [[buffer(BufferIndexUniforms)]]) {
    // Full-screen triangle vertices (oversized triangle technique)
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0)
    };

    float2 texCoords[3] = {
        float2(0.0, 1.0),
        float2(2.0, 1.0),
        float2(0.0, -1.0)
    };

    FragmentIn out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];

    return out;
}

// MARK: - Fragment Shader

/// Transform UV coordinates using the inverse canvas transform
float2 transformUV(float2 uv, float2 canvasSize, float2 imageSize, matrix_float3x3 inverseTransform) {
    // Convert UV to screen coordinates
    float2 screenPos = uv * canvasSize;

    // Apply inverse transform to get image coordinates
    float3 transformed = inverseTransform * float3(screenPos, 1.0);
    float2 imagePos = transformed.xy;

    // Convert to UV in image space
    return imagePos / imageSize;
}

/// Apply contrast and brightness to a color
float4 applyContrastBrightness(float4 color, float contrast, float brightness) {
    // Contrast: scale around 0.5 (mid-gray)
    float3 adjusted = (color.rgb - 0.5) * contrast + 0.5;
    // Brightness: simple offset
    adjusted = adjusted + brightness;
    // Clamp to valid range
    adjusted = clamp(adjusted, 0.0, 1.0);
    return float4(adjusted, color.a);
}

/// Image-only fragment shader for blink annotation mode
/// No mask compositing, just image display with contrast/brightness
fragment float4 imageOnlyFragment(FragmentIn in [[stage_in]],
                                   texture2d<float, access::sample> imageTexture [[texture(TextureIndexImage)]],
                                   constant ImageUniforms &uniforms [[buffer(BufferIndexUniforms)]]) {

    constexpr sampler linearSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    // Transform UV to image space
    float2 imageUV = transformUV(in.texCoord, uniforms.canvasSize, uniforms.imageSize, uniforms.inverseTransform);

    // Check if UV is within image bounds
    if (imageUV.x < 0.0 || imageUV.x > 1.0 || imageUV.y < 0.0 || imageUV.y > 1.0) {
        // Background color (dark gray)
        return float4(0.2, 0.2, 0.2, 1.0);
    }

    // Sample source image with bilinear filtering
    float4 imageColor = imageTexture.sample(linearSampler, imageUV);

    // Apply contrast and brightness
    imageColor = applyContrastBrightness(imageColor, uniforms.imageContrast, uniforms.imageBrightness);

    // Return opaque result
    imageColor.a = 1.0;
    return imageColor;
}
