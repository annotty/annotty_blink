import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Export sheet for blink annotation export
struct ExportSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: CanvasViewModel

    @State private var exportImages = true
    @State private var exportMasks = true
    @State private var exportJSON = true
    @State private var isExporting = false
    @State private var exportComplete = false
    @State private var showingShareSheet = false
    @State private var exportedFolderURL: URL?
    @State private var exportedFileCount = 0
    @State private var errorMessage: String?
    @State private var selectedExportURL: URL?
    @State private var showingFolderPicker = false

    /// Detect if running as iOS app on Mac
    private var isRunningOnMac: Bool {
        #if os(macOS)
        return true
        #else
        return ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Export contents section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Export Contents")
                        .font(.headline)

                    Toggle(isOn: $exportImages) {
                        HStack {
                            Image(systemName: "photo")
                            VStack(alignment: .leading) {
                                Text("Original Images")
                                Text("Copy source images to images/ folder")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }

                    Toggle(isOn: $exportMasks) {
                        HStack {
                            Image(systemName: "square.on.square")
                            VStack(alignment: .leading) {
                                Text("Label Masks")
                                Text("Annotation masks in labels/ folder")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }

                    Toggle(isOn: $exportJSON) {
                        HStack {
                            Image(systemName: "doc.text")
                            VStack(alignment: .leading) {
                                Text("JSON Coordinates")
                                Text("Line positions in normalized 0-1 format")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(PlatformColor.secondarySystemBackground))
                .cornerRadius(12)

                // Export destination picker (Mac only)
                if isRunningOnMac {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Export Destination")
                            .font(.headline)

                        HStack {
                            Image(systemName: "folder")
                            if let url = selectedExportURL {
                                Text(url.path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("Default: labels/ folder")
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Button("Choose...") {
                                showingFolderPicker = true
                            }
                        }
                    }
                    .padding()
                    .background(Color(PlatformColor.secondarySystemBackground))
                    .cornerRadius(12)
                }

                // Export button
                Button(action: performExport) {
                    HStack {
                        if isExporting {
                            ProgressView()
                                #if os(iOS)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                #endif
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text(isExporting ? "Exporting..." : "Export All Frames")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canExport ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(!canExport || isExporting)

                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.red)
                    }
                    .font(.caption)
                }

                if exportComplete, let folderURL = exportedFolderURL {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Export complete!")
                        }
                        Text("\(exportedFileCount) files in \(folderURL.lastPathComponent)/")
                            .font(.caption)
                            .foregroundColor(.gray)

                        if isRunningOnMac {
                            Button("Show in Finder") {
                                openInFinder()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Share Folder") {
                                showingShareSheet = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Spacer()

                // Info text - folder structure preview
                VStack(alignment: .leading, spacing: 4) {
                    Text("Export folder structure:")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("  Annotty_export_[timestamp]/")
                        .font(.caption.monospaced())
                        .foregroundColor(.gray)
                    if exportImages {
                        Text("    ├── images/")
                            .font(.caption.monospaced())
                            .foregroundColor(.gray)
                    }
                    if exportMasks {
                        Text("    ├── labels/")
                            .font(.caption.monospaced())
                            .foregroundColor(.gray)
                    }
                    if exportJSON {
                        Text("    └── blink_annotations.json")
                            .font(.caption.monospaced())
                            .foregroundColor(.gray)
                    }
                    Text("Annotated frames: \(viewModel.annotations.count)")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
            .navigationTitle("Export Annotations")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showingShareSheet) {
                if let folderURL = exportedFolderURL {
                    ShareSheet(items: [folderURL])
                }
            }
            #endif
            .fileImporter(
                isPresented: $showingFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        // Start accessing security-scoped resource
                        _ = url.startAccessingSecurityScopedResource()
                        selectedExportURL = url
                    }
                case .failure:
                    break
                }
            }
        }
    }

    private var canExport: Bool {
        exportImages || exportMasks || exportJSON
    }

    /// Open export folder in Finder (works on both native macOS and iOS-on-Mac)
    private func openInFinder() {
        guard let folderURL = exportedFolderURL else { return }

        #if os(macOS)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
        #else
        // iOS on Mac: Open folder URL to reveal in Finder
        UIApplication.shared.open(folderURL)
        #endif
    }

    private func performExport() {
        isExporting = true
        errorMessage = nil
        exportComplete = false
        exportedFolderURL = nil
        exportedFileCount = 0

        // Capture values on MainActor before entering detached task
        let shouldExportImages = exportImages
        let shouldExportJSON = exportJSON
        let shouldExportMasks = exportMasks
        let annotationsCopy = viewModel.annotations
        let customExportURL = selectedExportURL
        let projectRoot = ProjectFileService.shared.projectRoot
        let imageURLs = ProjectFileService.shared.getImageURLs()
        let exporter = PNGExporter()

        Task.detached(priority: .userInitiated) {
            let didStartAccessing = customExportURL?.startAccessingSecurityScopedResource() ?? false
            defer {
                if didStartAccessing {
                    customExportURL?.stopAccessingSecurityScopedResource()
                }
            }

            do {
                var fileCount = 0

                let baseDir: URL
                if let customURL = customExportURL {
                    baseDir = customURL
                } else if let root = projectRoot {
                    baseDir = root
                } else {
                    throw ExportError.outputDirectoryNotFound
                }

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
                let timestamp = dateFormatter.string(from: Date())
                let exportFolderName = "Annotty_export_\(timestamp)"
                let exportDir = baseDir.appendingPathComponent(exportFolderName)

                try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

                if shouldExportImages {
                    let imagesDir = exportDir.appendingPathComponent("images")
                    try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

                    for imageURL in imageURLs {
                        let destURL = imagesDir.appendingPathComponent(imageURL.lastPathComponent)
                        try FileManager.default.copyItem(at: imageURL, to: destURL)
                        fileCount += 1
                    }
                }

                if shouldExportMasks {
                    let labelsDir = exportDir.appendingPathComponent("labels")
                    try FileManager.default.createDirectory(at: labelsDir, withIntermediateDirectories: true)

                    for imageURL in imageURLs {
                        let baseName = imageURL.deletingPathExtension().lastPathComponent
                        guard let annotation = annotationsCopy[baseName] else { continue }

                        let outputURL = labelsDir.appendingPathComponent("\(baseName)_label.png")
                        try await MainActor.run {
                            try exporter.exportMask(
                                imageURL: imageURL,
                                annotation: annotation,
                                outputURL: outputURL
                            )
                        }
                        fileCount += 1
                    }
                }

                if shouldExportJSON {
                    let jsonURL = exportDir.appendingPathComponent("blink_annotations.json")
                    let annotationArray = annotationsCopy.values.sorted { $0.imageName < $1.imageName }

                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let jsonData = try encoder.encode(annotationArray)
                    try jsonData.write(to: jsonURL)
                    fileCount += 1
                }

                let finalCount = fileCount
                await MainActor.run {
                    self.exportedFolderURL = exportDir
                    self.exportedFileCount = finalCount
                    self.exportComplete = true
                    self.isExporting = false
                }

            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isExporting = false
                }
            }
        }
    }
}

// MARK: - iOS Share Sheet

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Preview

#Preview {
    ExportSheetView(viewModel: CanvasViewModel())
}
