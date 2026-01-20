import Foundation

/// Manages project folder structure and file operations
/// Folder structure:
/// - images/      : Source images
/// - annotations/ : Editable color PNG masks
/// - labels/      : Export output (PNG/COCO/YOLO)
class ProjectFileService {
    // MARK: - Singleton

    static let shared = ProjectFileService()

    // MARK: - Folder Names

    static let imagesFolderName = "images"
    static let annotationsFolderName = "annotations"
    static let labelsFolderName = "labels"

    // MARK: - Paths

    private(set) var projectRoot: URL?
    private(set) var imagesFolder: URL?
    private(set) var annotationsFolder: URL?
    private(set) var labelsFolder: URL?

    /// Convenience accessor for labels URL
    var labelsURL: URL? { labelsFolder }

    // MARK: - File Manager

    private let fileManager = FileManager.default

    // MARK: - Initialization

    private init() {}

    // MARK: - Project Setup

    /// Initialize project at the given root directory
    /// Creates folder structure if it doesn't exist
    func initializeProject(at rootURL: URL) throws {
        projectRoot = rootURL

        // Create folder URLs
        imagesFolder = rootURL.appendingPathComponent(Self.imagesFolderName)
        annotationsFolder = rootURL.appendingPathComponent(Self.annotationsFolderName)
        labelsFolder = rootURL.appendingPathComponent(Self.labelsFolderName)

        // Create folders if they don't exist
        try createFolderIfNeeded(imagesFolder!)
        try createFolderIfNeeded(annotationsFolder!)
        try createFolderIfNeeded(labelsFolder!)
    }

    /// Create folder if it doesn't exist
    private func createFolderIfNeeded(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Image Operations

    /// Get all image URLs in the images folder
    func getImageURLs() -> [URL] {
        guard let imagesFolder = imagesFolder else { return [] }

        let supportedExtensions = ["png", "jpg", "jpeg"]

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: imagesFolder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            return contents
                .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            print("Failed to read images folder: \(error)")
            return []
        }
    }

    // MARK: - Annotation Operations

    /// Get annotation URL for a given image
    func getAnnotationURL(for imageURL: URL) -> URL? {
        guard let annotationsFolder = annotationsFolder else { return nil }

        let baseName = imageURL.deletingPathExtension().lastPathComponent
        let annotationURL = annotationsFolder
            .appendingPathComponent(baseName)
            .appendingPathExtension("png")

        return annotationURL
    }

    /// Check if annotation exists for a given image
    func annotationExists(for imageURL: URL) -> Bool {
        guard let annotationURL = getAnnotationURL(for: imageURL) else { return false }
        return fileManager.fileExists(atPath: annotationURL.path)
    }

    /// Save annotation PNG
    func saveAnnotation(_ imageData: Data, for imageURL: URL) throws {
        guard let annotationURL = getAnnotationURL(for: imageURL) else {
            throw ProjectFileError.invalidPath
        }

        try imageData.write(to: annotationURL)
    }

    /// Load annotation PNG data
    func loadAnnotation(for imageURL: URL) -> Data? {
        guard let annotationURL = getAnnotationURL(for: imageURL),
              fileManager.fileExists(atPath: annotationURL.path) else {
            return nil
        }

        return try? Data(contentsOf: annotationURL)
    }

    // MARK: - Label Operations

    /// Get label URL for a given image and format
    func getLabelURL(for imageURL: URL, format: ExportFormat) -> URL? {
        guard let labelsFolder = labelsFolder else { return nil }

        let baseName = imageURL.deletingPathExtension().lastPathComponent

        switch format {
        case .png:
            return labelsFolder.appendingPathComponent(baseName).appendingPathExtension("png")
        case .coco:
            return labelsFolder.appendingPathComponent(baseName).appendingPathExtension("json")
        case .yolo:
            return labelsFolder.appendingPathComponent(baseName).appendingPathExtension("txt")
        }
    }

    /// Save label file
    func saveLabel(_ data: Data, for imageURL: URL, format: ExportFormat) throws {
        guard let labelURL = getLabelURL(for: imageURL, format: format) else {
            throw ProjectFileError.invalidPath
        }

        try data.write(to: labelURL)
    }

    // MARK: - Copy Image to Project

    /// Copy an image to the project's images folder
    func copyImageToProject(_ sourceURL: URL) throws -> URL {
        guard let imagesFolder = imagesFolder else {
            throw ProjectFileError.projectNotInitialized
        }

        let destinationURL = imagesFolder.appendingPathComponent(sourceURL.lastPathComponent)

        // Remove existing file if present
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    // MARK: - Delete Image

    /// Delete an image and its associated annotation file
    func deleteImage(_ imageURL: URL) throws {
        // Delete the image file
        if fileManager.fileExists(atPath: imageURL.path) {
            try fileManager.removeItem(at: imageURL)
        }

        // Delete the annotation file if it exists
        if let annotationURL = getAnnotationURL(for: imageURL),
           fileManager.fileExists(atPath: annotationURL.path) {
            try fileManager.removeItem(at: annotationURL)
        }

        // Delete the label file if it exists
        if let labelsFolder = labelsFolder {
            let baseName = imageURL.deletingPathExtension().lastPathComponent
            let labelURL = labelsFolder.appendingPathComponent("\(baseName)_label.png")
            if fileManager.fileExists(atPath: labelURL.path) {
                try fileManager.removeItem(at: labelURL)
            }
        }
    }

    // MARK: - Clear All Data

    /// Delete all images, annotations, and labels
    func clearAllData() throws {
        // Delete all images
        if let imagesFolder = imagesFolder {
            try clearFolderContents(imagesFolder)
        }

        // Delete all annotations
        if let annotationsFolder = annotationsFolder {
            try clearFolderContents(annotationsFolder)
        }

        // Delete all labels
        if let labelsFolder = labelsFolder {
            try clearFolderContents(labelsFolder)
        }

        print("[ProjectFileService] Cleared all data")
    }

    /// Clear contents of a folder (but keep the folder itself)
    private func clearFolderContents(_ folderURL: URL) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for fileURL in contents {
            try fileManager.removeItem(at: fileURL)
        }
    }
}

// MARK: - Export Format

enum ExportFormat {
    case png
    case coco
    case yolo
}

// MARK: - Errors

enum ProjectFileError: Error, LocalizedError {
    case projectNotInitialized
    case invalidPath
    case folderCreationFailed

    var errorDescription: String? {
        switch self {
        case .projectNotInitialized:
            return "Project has not been initialized"
        case .invalidPath:
            return "Invalid file path"
        case .folderCreationFailed:
            return "Failed to create folder"
        }
    }
}
