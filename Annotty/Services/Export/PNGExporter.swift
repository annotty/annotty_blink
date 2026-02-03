import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Export mode for blink annotations
enum BlinkExportMode {
    /// Export mask only (lines on black background) as {basename}_label.png
    case maskOnly
    /// Export JSON coordinates only
    case jsonOnly
}

/// Exports mask images with blink annotation lines
final class PNGExporter: Sendable {

    func exportMask(
        imageURL: URL,
        annotation: BlinkAnnotation,
        outputURL: URL
    ) throws {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ExportError.cannotLoadImage
        }

        let width = cgImage.width
        let height = cgImage.height

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

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        drawAnnotationLines(context: context, annotation: annotation, width: width, height: height)

        guard let outputImage = context.makeImage() else {
            throw ExportError.cannotCreateImage
        }

        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ExportError.cannotEncodePNG
        }
        CGImageDestinationAddImage(dest, outputImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ExportError.cannotEncodePNG
        }
    }

    /// Draw all annotation lines on the context
    private func drawAnnotationLines(
        context: CGContext,
        annotation: BlinkAnnotation,
        width: Int,
        height: Int
    ) {
        let lineWidth: CGFloat = 1.0

        for lineType in BlinkLineType.allCases {
            guard annotation.isLineVisible(lineType) else { continue }

            let position = annotation.getLinePosition(for: lineType)
            let color = lineType.rgbColor

            context.setStrokeColor(
                red: CGFloat(color.r) / 255.0,
                green: CGFloat(color.g) / 255.0,
                blue: CGFloat(color.b) / 255.0,
                alpha: 1.0
            )
            context.setLineWidth(lineWidth)

            if lineType.isVertical {
                let x = CGFloat(width) * position

                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: CGFloat(height)))
            } else {
                let verticalLine = lineType.verticalLineForEye
                let verticalX = annotation.getLinePosition(for: verticalLine)
                let y = CGFloat(height) * position

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

    func exportAsJSON(annotation: BlinkAnnotation) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(annotation)
    }

    func batchExportMasks(
        imageURLs: [URL],
        annotations: [String: BlinkAnnotation],
        outputDirectory: URL
    ) throws -> [URL] {
        var exportedURLs: [URL] = []

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for imageURL in imageURLs {
            let baseName = imageURL.deletingPathExtension().lastPathComponent
            guard let annotation = annotations[baseName] else { continue }

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
