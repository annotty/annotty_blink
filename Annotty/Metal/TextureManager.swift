import Foundation
import Metal
import MetalKit
import CoreGraphics
import UIKit

/// Manages Metal textures for image display
/// Simplified for line-based annotation (no mask textures)
class TextureManager {
    private let device: MTLDevice
    private let textureLoader: MTKTextureLoader

    /// Currently loaded source image texture
    private(set) var imageTexture: MTLTexture?

    /// Source image size
    private(set) var imageSize: CGSize = .zero

    /// Scale factor (kept for coordinate transforms)
    private(set) var maskScaleFactor: Float = 1.0

    init(device: MTLDevice) {
        self.device = device
        self.textureLoader = MTKTextureLoader(device: device)
    }

    // MARK: - Image Loading

    /// Load source image from URL using MTKTextureLoader (GPU-accelerated)
    func loadImage(from url: URL) throws {
        // Use MTKTextureLoader for fast GPU-accelerated loading
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.shared.rawValue,
            .SRGB: false
        ]

        let texture = try textureLoader.newTexture(URL: url, options: options)
        imageTexture = texture

        let width = texture.width
        let height = texture.height
        imageSize = CGSize(width: width, height: height)

        // Set scale factor to 1.0 (no mask scaling needed)
        maskScaleFactor = 1.0

        print("[TextureManager] Loaded image: \(width)x\(height)")
    }

    /// Load source image from CGImage (fallback for in-memory images)
    func loadImage(_ cgImage: CGImage) throws {
        let width = cgImage.width
        let height = cgImage.height
        imageSize = CGSize(width: width, height: height)

        // Use MTKTextureLoader for CGImage too
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.shared.rawValue,
            .SRGB: false
        ]

        let texture = try textureLoader.newTexture(cgImage: cgImage, options: options)
        imageTexture = texture

        maskScaleFactor = 1.0

        print("[TextureManager] Loaded image from CGImage: \(width)x\(height)")
    }

    /// Clear all textures
    func clear() {
        imageTexture = nil
        imageSize = .zero
    }
}

// MARK: - Errors

enum TextureError: Error, LocalizedError {
    case invalidImage
    case textureCreationFailed
    case noImageLoaded

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Failed to load image"
        case .textureCreationFailed:
            return "Failed to create Metal texture"
        case .noImageLoaded:
            return "No image loaded"
        }
    }
}
