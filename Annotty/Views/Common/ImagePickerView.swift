import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Image/Video picker for selecting images, folders, or videos
struct ImagePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onImageSelected: (URL) -> Void
    let onFolderSelected: (URL) -> Void
    let onProjectSelected: (URL) -> Void
    let onVideoSelected: (URL) -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var showingImagePicker = false
    @State private var showingFolderPicker = false
    @State private var showingProjectPicker = false
    @State private var showingVideoPicker = false
    @State private var showingFPSSelection = false
    @State private var selectedVideoURL: URL?
    @State private var selectedFPS: Double = 30.0
    @State private var isExtractingFrames = false
    @State private var extractionProgress: Double = 0.0

    private let fpsOptions: [Double] = [1, 5, 10, 15, 30, 60]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.blue)

                Spacer()

                Text("Import")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button("Cancel") { }
                    .opacity(0)
            }
            .padding()
            .background(Color(white: 0.15))

            // Content
            if isExtractingFrames {
                // Frame extraction progress view
                extractionProgressView
            } else if showingFPSSelection {
                // FPS selection view
                fpsSelectionView
            } else {
                // Main import options
                importOptionsView
            }
        }
        .background(Color(white: 0.1))
        .sheet(isPresented: $showingImagePicker) {
            DocumentPickerView(contentTypes: [.image]) { url in
                handleImageImport(url)
            }
        }
        .sheet(isPresented: $showingFolderPicker) {
            DocumentPickerView(contentTypes: [.folder]) { url in
                onFolderSelected(url)
                dismiss()
            }
        }
        .sheet(isPresented: $showingProjectPicker) {
            DocumentPickerView(contentTypes: [.folder]) { url in
                onProjectSelected(url)
                dismiss()
            }
        }
        .sheet(isPresented: $showingVideoPicker) {
            DocumentPickerView(contentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie]) { url in
                handleVideoSelection(url)
            }
        }
    }

    // MARK: - Import Options View

    private var importOptionsView: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 20)

            // Photos Library
            PhotosPicker(selection: $selectedItem, matching: .images) {
                HStack {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title2)
                    Text("From Photos Library")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .onChange(of: selectedItem) { _, newItem in
                Task { await loadImage(from: newItem) }
            }

            // Single image
            Button(action: { showingImagePicker = true }) {
                HStack {
                    Image(systemName: "doc.badge.plus")
                        .font(.title2)
                    Text("Single Image from Files")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            // Folder
            Button(action: { showingFolderPicker = true }) {
                HStack {
                    Image(systemName: "folder.badge.plus")
                        .font(.title2)
                    Text("Folder (Multiple Images)")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            // Video
            Button(action: { showingVideoPicker = true }) {
                HStack {
                    Image(systemName: "video.badge.plus")
                        .font(.title2)
                    Text("Video (Extract Frames)")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.cyan)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            Divider()
                .background(Color.gray)
                .padding(.vertical, 10)

            // Open Project
            Button(action: { showingProjectPicker = true }) {
                HStack {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.title2)
                    Text("Open Project Folder")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            Spacer()

            Text("Import: copy images to current project\nOpen Project: switch to different project")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - FPS Selection View

    private var fpsSelectionView: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)

            Text("Select Frame Rate")
                .font(.title2)
                .foregroundColor(.white)

            Text("Choose how many frames per second to extract from the video")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer().frame(height: 20)

            // FPS options
            ForEach(fpsOptions, id: \.self) { fps in
                Button(action: {
                    selectedFPS = fps
                }) {
                    HStack {
                        Text("\(Int(fps)) FPS")
                            .font(.headline)
                        Spacer()
                        if selectedFPS == fps {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.cyan)
                        }
                    }
                    .padding()
                    .background(selectedFPS == fps ? Color.cyan.opacity(0.2) : Color(white: 0.2))
                    .cornerRadius(10)
                }
                .foregroundColor(.white)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 20)

            // Action buttons
            HStack(spacing: 16) {
                Button(action: {
                    showingFPSSelection = false
                    selectedVideoURL = nil
                }) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(white: 0.3))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                Button(action: {
                    startFrameExtraction()
                }) {
                    Text("Extract Frames")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.cyan)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Extraction Progress View

    private var extractionProgressView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "film")
                .font(.system(size: 60))
                .foregroundColor(.cyan)

            Text("Extracting Frames...")
                .font(.title2)
                .foregroundColor(.white)

            ProgressView(value: extractionProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .cyan))
                .padding(.horizontal, 40)

            Text("\(Int(extractionProgress * 100))%")
                .font(.headline)
                .foregroundColor(.gray)

            Spacer()
        }
    }

    // MARK: - Actions

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item = item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("png")
                try data.write(to: tempURL)
                await MainActor.run {
                    onImageSelected(tempURL)
                    dismiss()
                }
            }
        } catch {
            print("[PhotosPicker] Failed: \(error)")
        }
    }

    private func handleImageImport(_ url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            try data.write(to: tempURL)
            onImageSelected(tempURL)
            dismiss()
        } catch {
            print("[ImageImport] Failed: \(error)")
        }
    }

    private func handleVideoSelection(_ url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()

        // Copy to temp directory for processing
        do {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)

            // Remove existing if present
            try? FileManager.default.removeItem(at: tempURL)

            let data = try Data(contentsOf: url)
            try data.write(to: tempURL)

            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }

            selectedVideoURL = tempURL
            showingFPSSelection = true
        } catch {
            print("[VideoImport] Failed: \(error)")
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    private func startFrameExtraction() {
        guard let videoURL = selectedVideoURL else { return }

        showingFPSSelection = false
        isExtractingFrames = true
        extractionProgress = 0.0

        Task {
            do {
                let extractor = VideoFrameExtractor()
                let frameURLs = try await extractor.extractFrames(
                    from: videoURL,
                    fps: selectedFPS
                ) { progress in
                    Task { @MainActor in
                        extractionProgress = progress
                    }
                }

                await MainActor.run {
                    isExtractingFrames = false
                    // Import extracted frames
                    for frameURL in frameURLs {
                        onImageSelected(frameURL)
                    }
                    dismiss()
                }
            } catch {
                print("[FrameExtraction] Failed: \(error)")
                await MainActor.run {
                    isExtractingFrames = false
                    showingFPSSelection = true
                }
            }
        }
    }
}

// MARK: - Document Picker

struct DocumentPickerView: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (URL) -> Void

        init(onPicked: @escaping (URL) -> Void) {
            self.onPicked = onPicked
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPicked(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}

// MARK: - Preview

#Preview {
    ImagePickerView(
        onImageSelected: { url in print("Image: \(url)") },
        onFolderSelected: { url in print("Folder: \(url)") },
        onProjectSelected: { url in print("Project: \(url)") },
        onVideoSelected: { url in print("Video: \(url)") }
    )
}
