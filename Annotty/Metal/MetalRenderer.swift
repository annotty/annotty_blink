import Foundation
import Metal
import MetalKit
import simd
import Combine

/// Main Metal rendering coordinator for image display
/// Simplified for line-based annotation (no mask/brush operations)
class MetalRenderer: NSObject, ObservableObject {
    // MARK: - Metal Objects

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let textureManager: TextureManager

    private var renderPipelineState: MTLRenderPipelineState?

    // MARK: - Uniforms

    /// Image contrast (0.0 - 2.0, 1.0 = normal)
    @Published var imageContrast: Float = 1.0
    /// Image brightness (-1.0 to 1.0, 0.0 = normal)
    @Published var imageBrightness: Float = 0.0

    // MARK: - State

    @Published var canvasTransform = CanvasTransform()
    private(set) var viewportSize: CGSize = .zero
    private(set) var contentScaleFactor: CGFloat = 1.0

    // MARK: - State Flags

    private(set) var isPipelineReady: Bool = false

    // MARK: - Initialization

    override init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create command queue")
        }

        self.device = device
        self.commandQueue = commandQueue
        self.textureManager = TextureManager(device: device)

        super.init()

        do {
            try setupPipelines()
            isPipelineReady = true
            print("✅ MetalRenderer initialized (simplified for line annotations)")
        } catch {
            print("⚠️ Metal pipeline setup failed: \(error)")
            isPipelineReady = false
        }
    }

    // MARK: - Pipeline Setup

    private func setupPipelines() throws {
        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.libraryCreationFailed
        }

        // Render pipeline for canvas (image display only)
        let renderDescriptor = MTLRenderPipelineDescriptor()
        renderDescriptor.vertexFunction = library.makeFunction(name: "canvasVertex")
        renderDescriptor.fragmentFunction = library.makeFunction(name: "imageOnlyFragment")
        renderDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Enable blending
        renderDescriptor.colorAttachments[0].isBlendingEnabled = true
        renderDescriptor.colorAttachments[0].rgbBlendOperation = .add
        renderDescriptor.colorAttachments[0].alphaBlendOperation = .add
        renderDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        renderDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        renderDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        renderDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        renderPipelineState = try device.makeRenderPipelineState(descriptor: renderDescriptor)
    }

    // MARK: - Rendering

    /// Main render function called by MTKView
    func render(to drawable: CAMetalDrawable, with renderPassDescriptor: MTLRenderPassDescriptor) {
        guard let renderPipelineState = renderPipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        // Skip rendering if no image is loaded
        guard textureManager.imageTexture != nil else {
            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        renderEncoder.setRenderPipelineState(renderPipelineState)

        // Set uniforms
        var uniforms = createUniforms()
        let uniformsSize = MemoryLayout<ImageUniforms>.stride
        renderEncoder.setVertexBytes(&uniforms, length: uniformsSize, index: 0)
        renderEncoder.setFragmentBytes(&uniforms, length: uniformsSize, index: 0)

        // Set textures
        if let imageTexture = textureManager.imageTexture {
            renderEncoder.setFragmentTexture(imageTexture, index: 0)
        }

        // Draw full-screen triangle
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Create uniforms structure for shaders
    private func createUniforms() -> ImageUniforms {
        return ImageUniforms(
            transform: canvasTransform.toSimdMatrix(),
            inverseTransform: canvasTransform.toInverseSimdMatrix(),
            imageContrast: imageContrast,
            imageBrightness: imageBrightness,
            canvasSize: simd_float2(Float(viewportSize.width), Float(viewportSize.height)),
            imageSize: simd_float2(Float(textureManager.imageSize.width), Float(textureManager.imageSize.height))
        )
    }

    // MARK: - Image Loading

    /// Load image from URL
    func loadImage(from url: URL) throws {
        try textureManager.loadImage(from: url)
        canvasTransform.maskScaleFactor = textureManager.maskScaleFactor
    }

    /// Load image from CGImage
    func loadImage(_ cgImage: CGImage) throws {
        try textureManager.loadImage(cgImage)
        canvasTransform.maskScaleFactor = textureManager.maskScaleFactor
    }

    /// Clear the current image
    func clearImage() {
        textureManager.clear()
    }

    // MARK: - Viewport

    /// Update viewport size and scale factor
    func updateViewportSize(_ size: CGSize, scaleFactor: CGFloat = 1.0) {
        viewportSize = size
        contentScaleFactor = scaleFactor
    }

    /// Convert touch point (in points) to screen coordinates (in pixels)
    func convertTouchToScreen(_ point: CGPoint) -> CGPoint {
        return CGPoint(
            x: point.x * contentScaleFactor,
            y: point.y * contentScaleFactor
        )
    }
}

// MARK: - ImageUniforms

/// Simplified uniforms for image-only rendering
struct ImageUniforms {
    var transform: simd_float3x3
    var inverseTransform: simd_float3x3
    var imageContrast: Float
    var imageBrightness: Float
    var canvasSize: simd_float2
    var imageSize: simd_float2
}

// MARK: - Errors

enum RendererError: Error, LocalizedError {
    case libraryCreationFailed
    case functionNotFound(String)
    case pipelineCreationFailed

    var errorDescription: String? {
        switch self {
        case .libraryCreationFailed:
            return "Failed to create Metal library"
        case .functionNotFound(let name):
            return "Metal function not found: \(name)"
        case .pipelineCreationFailed:
            return "Failed to create pipeline state"
        }
    }
}
