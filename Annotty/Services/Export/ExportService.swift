import Foundation
import CoreGraphics

/// Coordinates export operations for blink annotations
class ExportService {
    // MARK: - Singleton

    static let shared = ExportService()

    // MARK: - Exporters

    private let pngExporter = PNGExporter()

    // MARK: - Dependencies

    private let projectService = ProjectFileService.shared

    // MARK: - Initialization

    private init() {}

    // MARK: - Export

    /// Export blink annotations as mask images
    /// - Parameters:
    ///   - annotations: Dictionary of image name to annotation
    ///   - imageURLs: Source image URLs
    ///   - mode: Export mode (maskOnly, jsonOnly)
    /// - Returns: URLs of exported files
    func exportBlinkAnnotations(
        annotations: [String: BlinkAnnotation],
        imageURLs: [URL],
        mode: BlinkExportMode
    ) throws -> [URL] {
        var exportedURLs: [URL] = []

        guard let labelsDir = projectService.labelsURL else {
            throw ExportError.outputDirectoryNotFound
        }

        // Create output directory
        try FileManager.default.createDirectory(at: labelsDir, withIntermediateDirectories: true)

        // Export mask images if not JSON-only mode
        if mode != .jsonOnly {
            for imageURL in imageURLs {
                let baseName = imageURL.deletingPathExtension().lastPathComponent

                // Skip images without annotations
                guard let annotation = annotations[baseName] else { continue }

                // Output as {basename}_label.png
                let outputURL = labelsDir.appendingPathComponent("\(baseName)_label.png")

                try pngExporter.exportMask(
                    imageURL: imageURL,
                    annotation: annotation,
                    outputURL: outputURL
                )

                exportedURLs.append(outputURL)
            }
        }

        return exportedURLs
    }

    /// Export annotations as JSON
    func exportAnnotationsJSON(annotations: [String: BlinkAnnotation]) throws -> URL {
        guard let labelsDir = projectService.labelsURL else {
            throw ExportError.outputDirectoryNotFound
        }

        let jsonURL = labelsDir.appendingPathComponent("blink_annotations.json")
        let annotationArray = annotations.values.sorted { $0.imageName < $1.imageName }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(annotationArray)
        try jsonData.write(to: jsonURL)

        return jsonURL
    }
}
