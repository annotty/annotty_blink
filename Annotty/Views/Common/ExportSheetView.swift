import SwiftUI

/// Export sheet for blink annotation export
struct ExportSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: CanvasViewModel

    @State private var exportMasks = true
    @State private var exportJSON = true
    @State private var isExporting = false
    @State private var exportComplete = false
    @State private var showingShareSheet = false
    @State private var exportedURLs: [URL] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Mask export option
                VStack(alignment: .leading, spacing: 16) {
                    Text("Mask Export")
                        .font(.headline)

                    Toggle(isOn: $exportMasks) {
                        HStack {
                            Image(systemName: "square.on.square")
                            VStack(alignment: .leading) {
                                Text("Label Masks")
                                Text("Black background with colored lines as {basename}_label.png")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)

                // JSON export toggle
                VStack(alignment: .leading, spacing: 16) {
                    Text("Data Export")
                        .font(.headline)

                    Toggle(isOn: $exportJSON) {
                        HStack {
                            Image(systemName: "doc.text")
                            VStack(alignment: .leading) {
                                Text("JSON Coordinates")
                                Text("All line positions in normalized 0-1 format")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)

                // Export button
                Button(action: performExport) {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
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

                if exportComplete {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Export complete! \(exportedURLs.count) files")
                    }

                    Button("Share Files") {
                        showingShareSheet = true
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                // Info text
                VStack(spacing: 4) {
                    Text("Files will be saved to the labels/ folder")
                    Text("Annotated frames: \(viewModel.annotations.count)")
                }
                .font(.caption)
                .foregroundColor(.gray)
            }
            .padding(24)
            .navigationTitle("Export Annotations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if !exportedURLs.isEmpty {
                    ShareSheet(items: exportedURLs)
                }
            }
        }
    }

    private var canExport: Bool {
        exportMasks || exportJSON
    }

    private func performExport() {
        isExporting = true
        errorMessage = nil
        exportComplete = false
        exportedURLs = []

        Task {
            do {
                var urls: [URL] = []

                // Get labels directory
                guard let labelsDir = ProjectFileService.shared.labelsURL else {
                    throw ExportError.outputDirectoryNotFound
                }

                // Create output directory
                try FileManager.default.createDirectory(at: labelsDir, withIntermediateDirectories: true)

                let exporter = PNGExporter()

                // Export JSON if enabled
                if exportJSON {
                    let jsonURL = labelsDir.appendingPathComponent("blink_annotations.json")
                    let annotationArray = viewModel.annotations.values.sorted { $0.imageName < $1.imageName }

                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let jsonData = try encoder.encode(annotationArray)
                    try jsonData.write(to: jsonURL)
                    urls.append(jsonURL)
                }

                // Export mask images if enabled
                if exportMasks {
                    let imageURLs = ProjectFileService.shared.getImageURLs()

                    for imageURL in imageURLs {
                        let baseName = imageURL.deletingPathExtension().lastPathComponent

                        // Skip images without annotations
                        guard let annotation = viewModel.annotations[baseName] else { continue }

                        // Output as {basename}_label.png
                        let outputURL = labelsDir.appendingPathComponent("\(baseName)_label.png")

                        try exporter.exportMask(
                            imageURL: imageURL,
                            annotation: annotation,
                            outputURL: outputURL
                        )

                        urls.append(outputURL)
                    }
                }

                await MainActor.run {
                    exportedURLs = urls
                    exportComplete = true
                    isExporting = false
                }

            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }
}

/// UIKit share sheet wrapper
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    ExportSheetView(viewModel: CanvasViewModel())
}
