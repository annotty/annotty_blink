import Foundation
import CoreGraphics

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Export mode for blink annotations
enum BlinkExportMode {
    /// Export mask only (lines on black background) as {basename}_label.png
    case maskOnly
    /// Export JSON coordinates only
    case jsonOnly
}

/// Exports mask images with blink annotation lines
class PNGExporter {

    /// Export a mask image with annotation lines on black background
    /// - Parameters:
    ///   - imageURL: URL of the source image (used for dimensions)
    ///   - annotation: Blink annotation data
    ///   - outputURL: URL to save the mask image
    func exportMask(
        imageURL: URL,
        annotation: BlinkAnnotation,
        outputURL: URL
    ) throws {
        // Load source image to get dimensions
        guard let cgImage = loadCGImage(from: imageURL) else {
            throw ExportError.cannotLoadImage
        }

        let width = cgImage.width
        let height = cgImage.height

        // Create drawing context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw ExportError.cannotCreateContext
        }

        // Fill with black background
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw annotation lines on black background
        drawAnnotationLines(context: context, annotation: annotation, width: width, height: height)

        // Save as PNG
        guard let outputImage = context.makeImage() else {
            throw ExportError.cannotCreateImage
        }

        try saveCGImageAsPNG(outputImage, to: outputURL)
    }

    /// Load CGImage from file URL (cross-platform)
    private func loadCGImage(from url: URL) -> CGImage? {
        #if os(iOS)
        guard let uiImage = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        return uiImage.cgImage
        #elseif os(macOS)
        guard let nsImage = NSImage(contentsOfFile: url.path) else {
            return nil
        }
        return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }

    /// Save CGImage as PNG file (cross-platform)
    private func saveCGImageAsPNG(_ cgImage: CGImage, to url: URL) throws {
        #if os(iOS)
        let uiImage = UIImage(cgImage: cgImage)
        guard let pngData = uiImage.pngData() else {
            throw ExportError.cannotEncodePNG
        }
        try pngData.write(to: url)
        #elseif os(macOS)
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let nsImage = NSImage(cgImage: cgImage, size: size)
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.cannotEncodePNG
        }
        try pngData.write(to: url)
        #endif
    }

    /// Draw all annotation lines on the context
    private func drawAnnotationLines(
        context: CGContext,
        annotation: BlinkAnnotation,
        width: Int,
        height: Int
    ) {
        let lineWidth: CGFloat = 1.0

        // Draw each visible line
        for lineType in BlinkLineType.allCases {
            guard annotation.isLineVisible(lineType) else { continue }

            let position = annotation.getLinePosition(for: lineType)
            let color = lineType.rgbColor

            // Set stroke color
            context.setStrokeColor(
                red: CGFloat(color.r) / 255.0,
                green: CGFloat(color.g) / 255.0,
                blue: CGFloat(color.b) / 255.0,
                alpha: 1.0
            )
            context.setLineWidth(lineWidth)

            if lineType.isVertical {
                // Vertical line: full height at X position
                let x = CGFloat(width) * position

                // CoreGraphics has flipped Y (origin at bottom-left)
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: CGFloat(height)))
            } else {
                // Horizontal line: short line centered on vertical line
                let verticalLine = lineType.verticalLineForEye
                let verticalX = annotation.getLinePosition(for: verticalLine)
                let y = CGFloat(height) * position

                // Calculate horizontal extent (10 pixels on each side)
                let halfWidth = horizontalLineHalfWidth
                let centerX = CGFloat(width) * verticalX
                let startX = centerX - halfWidth
                let endX = centerX + halfWidth

                // CoreGraphics Y is flipped
                let flippedY = CGFloat(height) - y

                context.move(to: CGPoint(x: startX, y: flippedY))
                context.addLine(to: CGPoint(x: endX, y: flippedY))
            }

            context.strokePath()
        }
    }

    /// Export annotation as JSON
    func exportAsJSON(annotation: BlinkAnnotation) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(annotation)
    }

    /// Batch export mask images for all annotations
    /// - Parameters:
    ///   - imageURLs: Source image URLs
    ///   - annotations: Dictionary of image name to annotation
    ///   - outputDirectory: Directory to save mask images
    /// - Returns: URLs of exported mask images
    func batchExportMasks(
        imageURLs: [URL],
        annotations: [String: BlinkAnnotation],
        outputDirectory: URL
    ) throws -> [URL] {
        var exportedURLs: [URL] = []

        // Create output directory if needed
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for imageURL in imageURLs {
            let baseName = imageURL.deletingPathExtension().lastPathComponent

            // Skip images without annotations
            guard let annotation = annotations[baseName] else { continue }

            // Output as {basename}_label.png
            let outputURL = outputDirectory.appendingPathComponent("\(baseName)_label.png")

            try exportMask(
                imageURL: imageURL,
                annotation: annotation,
                outputURL: outputURL
            )

            exportedURLs.append(outputURL)
        }

        return exportedURLs
    }
}

// MARK: - Export Errors

enum ExportError: Error, LocalizedError {
    case cannotLoadImage
    case cannotCreateContext
    case cannotCreateImage
    case cannotEncodePNG
    case outputDirectoryNotFound

    var errorDescription: String? {
        switch self {
        case .cannotLoadImage:
            return "Cannot load source image"
        case .cannotCreateContext:
            return "Cannot create graphics context"
        case .cannotCreateImage:
            return "Cannot create output image"
        case .cannotEncodePNG:
            return "Cannot encode as PNG"
        case .outputDirectoryNotFound:
            return "Output directory not found"
        }
    }
}
