#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

/// Simplified uniforms for image-only rendering (blink annotation mode)
struct ImageUniforms {
    /// Canvas transform matrix (pan/zoom/rotate)
    matrix_float3x3 transform;
    /// Inverse of transform matrix
    matrix_float3x3 inverseTransform;
    /// Image contrast (0.0 - 2.0, 1.0 = normal)
    float imageContrast;
    /// Image brightness (-1.0 to 1.0, 0.0 = normal)
    float imageBrightness;
    /// Viewport size in pixels
    simd_float2 canvasSize;
    /// Source image size in pixels
    simd_float2 imageSize;
};

/// Buffer indices for shader bindings
enum BufferIndex {
    BufferIndexUniforms = 0,
    BufferIndexVertices = 1
};

/// Texture indices for shader bindings
enum TextureIndex {
    TextureIndexImage = 0
};

#endif /* ShaderTypes_h */
