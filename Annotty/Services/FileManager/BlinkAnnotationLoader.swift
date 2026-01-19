import Foundation

/// Service for loading and saving blink annotations as JSON
class BlinkAnnotationLoader {
    static let shared = BlinkAnnotationLoader()

    /// File name for storing annotations
    private let annotationsFileName = "blink_annotations.json"

    private init() {}

    /// Get the URL for the annotations JSON file
    private func getAnnotationsURL() -> URL? {
        guard let annotationsFolder = ProjectFileService.shared.annotationsFolder else {
            return nil
        }
        return annotationsFolder.appendingPathComponent(annotationsFileName)
    }

    /// Save all annotations to JSON file (keyed by image name for stability)
    func saveAnnotations(_ annotations: [String: BlinkAnnotation]) {
        guard let url = getAnnotationsURL() else {
            print("[BlinkAnnotationLoader] No project URL")
            return
        }

        // Convert dictionary to array for JSON encoding (sorted by image name)
        let annotationArray = annotations.values.sorted { $0.imageName < $1.imageName }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(annotationArray)
            try data.write(to: url, options: .atomic)
            print("[BlinkAnnotationLoader] Saved \(annotationArray.count) annotations to \(url.lastPathComponent)")
        } catch {
            print("[BlinkAnnotationLoader] Save failed: \(error)")
        }
    }

    /// Load all annotations from JSON file (keyed by image name)
    func loadAnnotations() -> [String: BlinkAnnotation] {
        guard let url = getAnnotationsURL() else {
            print("[BlinkAnnotationLoader] No project URL")
            return [:]
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[BlinkAnnotationLoader] No annotations file found")
            return [:]
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let annotationArray = try decoder.decode([BlinkAnnotation].self, from: data)

            // Convert array to dictionary indexed by imageName
            var annotations: [String: BlinkAnnotation] = [:]
            for annotation in annotationArray {
                annotations[annotation.imageName] = annotation
            }

            print("[BlinkAnnotationLoader] Loaded \(annotations.count) annotations from \(url.lastPathComponent)")
            return annotations
        } catch {
            print("[BlinkAnnotationLoader] Load failed: \(error)")
            return [:]
        }
    }

    /// Delete the annotations file
    func deleteAnnotations() {
        guard let url = getAnnotationsURL() else { return }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                print("[BlinkAnnotationLoader] Deleted annotations file")
            }
        } catch {
            print("[BlinkAnnotationLoader] Delete failed: \(error)")
        }
    }
}
