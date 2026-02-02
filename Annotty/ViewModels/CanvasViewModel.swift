import SwiftUI
import Combine
import simd

/// Main state coordinator for the blink annotation canvas
/// Manages line annotations, image navigation, and coordinates with Metal renderer
class CanvasViewModel: ObservableObject {
    // MARK: - Renderer

    @Published private(set) var renderer: MetalRenderer?

    // MARK: - Gesture Coordinator

    let gestureCoordinator = GestureCoordinator()

    // MARK: - Line Annotation State

    /// Current annotation for the active frame
    @Published var currentAnnotation: BlinkAnnotation?

    /// Currently selected line type for dragging
    @Published var selectedLineType: BlinkLineType = .leftPupilVertical

    /// All annotations indexed by image name (filename without extension)
    @Published var annotations: [String: BlinkAnnotation] = [:]

    /// Whether currently dragging a line
    @Published var isDraggingLine: Bool = false

    /// Last touch point during drag (for UI feedback)
    @Published var lastDragPoint: CGPoint = .zero

    /// Initial line position when drag started (for relative dragging)
    private var dragStartLinePosition: CGFloat = 0

    /// Initial touch point in normalized coordinates when drag started
    private var dragStartNormalizedPoint: CGPoint = .zero

    /// Current zoom scale for UI updates
    @Published var currentScale: CGFloat = 1.0

    /// Transform version counter - incremented on any transform change to trigger overlay re-render
    @Published var transformVersion: Int = 0

    // MARK: - Display Settings

    /// Image contrast (0.0 - 2.0, 1.0 = normal, 0% - 200%)
    @Published var imageContrast: Float = 1.0 {
        didSet {
            renderer?.imageContrast = imageContrast
        }
    }

    /// Image brightness (-1.0 to 1.0, 0.0 = normal)
    @Published var imageBrightness: Float = 0.0 {
        didSet {
            renderer?.imageBrightness = imageBrightness
        }
    }

    // MARK: - Image Navigation

    @Published private(set) var currentImageIndex: Int = 0
    @Published private(set) var totalImageCount: Int = 0

    /// Current image name (filename with extension) - used as annotation key in JSON
    var currentImageName: String? {
        imageManager.currentItem?.fileName
    }

    // MARK: - Loading/Saving State

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isSaving: Bool = false

    // MARK: - Undo Manager

    private var undoStack: [BlinkAnnotation] = []
    private var redoStack: [BlinkAnnotation] = []
    private let maxUndoSteps = 50

    // MARK: - Image Manager

    private let imageManager = ImageItemManager()

    // MARK: - View State

    private var viewSize: CGSize = .zero
    private var cancellables = Set<AnyCancellable>()

    /// Flag to track if annotation has been modified since last save
    private var annotationModified: Bool = false

    /// Import result message (for displaying errors or success)
    @Published var importResultMessage: String?

    /// Show import result alert
    @Published var showImportResultAlert: Bool = false

    /// UserDefaults key for last viewed image
    private static let lastImageNameKey = "annotty.lastImageName"

    /// UserDefaults key for auto-copy setting
    private static let autoCopySettingKey = "annotty.autoCopyPreviousAnnotation"

    /// Whether to auto-copy annotations from previous image when navigating
    @Published var autoCopyPreviousAnnotation: Bool = false {
        didSet {
            UserDefaults.standard.set(autoCopyPreviousAnnotation, forKey: Self.autoCopySettingKey)
        }
    }

    // MARK: - Initialization

    init() {
        print("🚀 CanvasViewModel init (Blink Annotation Mode)")

        // Load settings from UserDefaults
        autoCopyPreviousAnnotation = UserDefaults.standard.bool(forKey: Self.autoCopySettingKey)

        setupRenderer()
        setupBindings()
        setupGestureCallbacks()
        initializeProjectFolder()
    }

    /// Initialize the project folder structure and load existing images
    private func initializeProjectFolder() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[Project] Failed to get Documents directory")
            return
        }

        print("[Project] Root: \(documentsURL.path)")

        do {
            try ProjectFileService.shared.initializeProject(at: documentsURL)
            print("[Project] Folder structure: images/, annotations/, labels/")
            reloadImagesFromProject()
        } catch {
            print("[Project] Failed to initialize: \(error)")
        }
    }

    /// Open a different project folder
    func openProject(at folderURL: URL) {
        let didStartAccessing = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try ProjectFileService.shared.initializeProject(at: folderURL)
            print("[Project] Opened project: \(folderURL.lastPathComponent)")
            reloadImagesFromProject()
        } catch {
            print("[Project] Failed to open: \(error)")
        }
    }

    /// Reload images from the project's images folder
    func reloadImagesFromProject() {
        // Save current annotations before reloading to preserve work
        if annotationModified {
            saveCurrentAnnotation()
        }
        if !annotations.isEmpty {
            saveAllAnnotations()
        }

        let imageURLs = ProjectFileService.shared.getImageURLs()
        print("[Project] Found \(imageURLs.count) images")

        imageManager.setImages(imageURLs)

        // Load saved annotations (merges with any just-saved data)
        loadAllAnnotations()

        // Resume from last viewed image if it still exists
        if let lastImageName = UserDefaults.standard.string(forKey: Self.lastImageNameKey),
           let index = imageManager.items.firstIndex(where: { $0.fileName == lastImageName }) {
            imageManager.goTo(index: index)
            print("[Project] Resuming from: \(lastImageName)")
        }

        // Load current image with its annotation (if exists)
        if imageManager.currentItem != nil {
            loadCurrentImage()
        }
    }

    /// Import a single image to the project (appended at the end)
    /// Navigates to the imported image after completion
    func importImage(from sourceURL: URL) {
        importImages(from: [sourceURL])
    }

    /// Import multiple images to the project (appended at the end)
    /// Navigates to the FIRST imported image after completion
    func importImages(from sourceURLs: [URL]) {
        guard !sourceURLs.isEmpty else { return }

        // Save current annotations before import
        if annotationModified {
            saveCurrentAnnotation()
        }

        var copiedURLs: [URL] = []
        for sourceURL in sourceURLs {
            do {
                let destinationURL = try ProjectFileService.shared.copyImageToProject(sourceURL)
                copiedURLs.append(destinationURL)
                print("[Import] Copied: \(destinationURL.lastPathComponent)")
            } catch {
                print("[Import] Failed for \(sourceURL.lastPathComponent): \(error)")
            }
        }

        guard !copiedURLs.isEmpty else { return }

        // Append to the end instead of reloading (which would sort alphabetically)
        imageManager.appendImages(copiedURLs)

        // Navigate to the FIRST newly added image
        let firstNewIndex = imageManager.items.count - copiedURLs.count
        imageManager.goTo(index: firstNewIndex)
        loadCurrentImage()

        print("[Import] Imported \(copiedURLs.count) images, starting at index \(firstNewIndex)")
    }

    /// Import all images from a folder (appended at the end)
    func importImagesFromFolder(_ folderURL: URL) {
        // Save current annotations before import
        if annotationModified {
            saveCurrentAnnotation()
        }

        let fileManager = FileManager.default
        let supportedExtensions = ["png", "jpg", "jpeg"]

        let didStartAccessing = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            let imageFiles = contents.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            print("[Import] Found \(imageFiles.count) images in folder")

            var copiedURLs: [URL] = []
            for imageURL in imageFiles {
                if let copiedURL = try? ProjectFileService.shared.copyImageToProject(imageURL) {
                    copiedURLs.append(copiedURL)
                }
            }

            // Append to the end instead of reloading
            imageManager.appendImages(copiedURLs)

            // Navigate to the first newly added image
            if !copiedURLs.isEmpty {
                let firstNewIndex = imageManager.items.count - copiedURLs.count
                imageManager.goTo(index: firstNewIndex)
                loadCurrentImage()
            }
        } catch {
            print("[Import] Folder read failed: \(error)")
        }
    }

    /// Import annotation file (JSON) and merge with existing annotations
    ///
    /// Expected JSON format: Array of BlinkAnnotation objects
    /// - Matching images: Annotations are merged (imported overwrites existing)
    /// - Missing images: Annotations are still imported (images may be added later)
    /// - Invalid format: Shows error message
    func importAnnotationFile(from url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)

            // Validate JSON format
            let decoder = JSONDecoder()
            let importedAnnotations = try decoder.decode([BlinkAnnotation].self, from: data)

            // Get list of currently loaded images
            let imageNames = Set(imageManager.items.map { $0.fileName })

            // Merge with existing annotations
            var matchedCount = 0
            var unmatchedCount = 0
            for annotation in importedAnnotations {
                annotations[annotation.imageName] = annotation
                if imageNames.contains(annotation.imageName) {
                    matchedCount += 1
                } else {
                    unmatchedCount += 1
                }
            }

            // Update current annotation if it was imported
            if let currentName = currentImageName,
               let updatedAnnotation = annotations[currentName] {
                currentAnnotation = updatedAnnotation
            }

            // Save merged annotations
            saveAllAnnotations()

            // Show success message
            let message: String
            if unmatchedCount > 0 {
                message = "Imported \(importedAnnotations.count) annotations.\n(\(matchedCount) matched, \(unmatchedCount) without images)"
            } else {
                message = "Imported \(importedAnnotations.count) annotations."
            }
            importResultMessage = message
            showImportResultAlert = true

            print("[ImportAnnotation] \(message)")

        } catch let decodingError as DecodingError {
            // Invalid JSON format
            let errorMessage: String
            switch decodingError {
            case .dataCorrupted(let context):
                errorMessage = "Invalid JSON format: \(context.debugDescription)"
            case .keyNotFound(let key, _):
                errorMessage = "Missing required field: \(key.stringValue)"
            case .typeMismatch(let type, let context):
                errorMessage = "Type mismatch for \(type): \(context.debugDescription)"
            case .valueNotFound(let type, _):
                errorMessage = "Missing value for type: \(type)"
            @unknown default:
                errorMessage = "JSON parsing error: \(decodingError.localizedDescription)"
            }
            importResultMessage = errorMessage
            showImportResultAlert = true
            print("[ImportAnnotation] Error: \(errorMessage)")

        } catch {
            importResultMessage = "Failed to read file: \(error.localizedDescription)"
            showImportResultAlert = true
            print("[ImportAnnotation] Error: \(error)")
        }
    }

    /// Delete the current image and its annotation
    func deleteCurrentImage() {
        guard let item = imageManager.currentItem else { return }

        let imageName = item.fileName

        // Save any unsaved annotation first
        if annotationModified {
            saveCurrentAnnotation()
        }

        do {
            // Delete the image file and associated files
            try ProjectFileService.shared.deleteImage(item.url)
            print("[Delete] Deleted image: \(item.fileName)")

            // Remove annotation from memory
            annotations.removeValue(forKey: imageName)

            // Remove from image manager
            _ = imageManager.removeImage(at: currentImageIndex)

            // Save updated annotations
            saveAllAnnotations()

            // Load the new current image (if any)
            if imageManager.currentItem != nil {
                loadCurrentImage()
            } else {
                // No images left
                currentAnnotation = nil
                renderer?.textureManager.clear()
            }
        } catch {
            print("[Delete] Failed: \(error)")
        }
    }

    private func setupRenderer() {
        renderer = MetalRenderer()
    }

    private func setupGestureCallbacks() {
        // Line drag callbacks
        gestureCoordinator.onLineDragBegin = { [weak self] point in
            self?.beginLineDrag(at: point)
        }

        gestureCoordinator.onLineDragContinue = { [weak self] point in
            self?.continueLineDrag(to: point)
        }

        gestureCoordinator.onLineDragEnd = { [weak self] in
            self?.endLineDrag()
        }

        // Navigation callbacks
        gestureCoordinator.onPan = { [weak self] translation in
            self?.handlePan(translation: translation)
        }

        gestureCoordinator.onPinch = { [weak self] scale, center in
            self?.handlePinchDelta(scale: scale, at: center)
        }

        gestureCoordinator.onRotation = { [weak self] rotation, center in
            self?.handleRotationDelta(angle: rotation, at: center)
        }

        // Undo/Redo callbacks
        gestureCoordinator.onUndo = { [weak self] in
            self?.undo()
        }

        gestureCoordinator.onRedo = { [weak self] in
            self?.redo()
        }

        // Line nudge callbacks (up/down arrow keys)
        gestureCoordinator.onNudgeLineUp = { [weak self] in
            self?.nudgeLineUp()
        }

        gestureCoordinator.onNudgeLineDown = { [weak self] in
            self?.nudgeLineDown()
        }

        // Line selection callbacks (A/Z keys)
        gestureCoordinator.onSelectPreviousLine = { [weak self] in
            self?.selectPreviousLine()
        }

        gestureCoordinator.onSelectNextLine = { [weak self] in
            self?.selectNextLine()
        }

        // Image navigation callbacks (left/right arrow keys)
        gestureCoordinator.onPreviousImage = { [weak self] in
            self?.previousImage()
        }

        gestureCoordinator.onNextImage = { [weak self] in
            self?.nextImage()
        }
    }

    private func setupBindings() {
        // Sync image manager with published properties
        imageManager.$currentIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] index in
                self?.currentImageIndex = index
            }
            .store(in: &cancellables)

        imageManager.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.totalImageCount = items.count
            }
            .store(in: &cancellables)
    }

    // MARK: - View Size

    func updateViewSize(_ size: CGSize) {
        viewSize = size
        renderer?.updateViewportSize(size)
    }

    // MARK: - Image Loading

    func loadImage(from url: URL) {
        do {
            try renderer?.loadImage(from: url)
        } catch {
            print("Failed to load image: \(error)")
        }
    }

    // MARK: - Image Navigation

    func previousImage() {
        saveAndNavigate { [weak self] in
            self?.imageManager.previous()
        }
    }

    func nextImage() {
        saveAndNavigate { [weak self] in
            self?.imageManager.next()
        }
    }

    func goToImage(index: Int) {
        guard index != currentImageIndex else { return }
        saveAndNavigate { [weak self] in
            self?.imageManager.goTo(index: index)
        }
    }

    /// Save current annotation, navigate, then load
    private func saveAndNavigate(navigation: @escaping () -> Void) {
        // Save current annotation if modified
        if annotationModified {
            saveCurrentAnnotation()
        }

        // Preserve current scale before navigation
        let preservedScale = currentScale

        // Navigate
        navigation()
        loadCurrentImage(preservingScale: preservedScale)
    }

    private func loadCurrentImage(preservingScale: CGFloat? = nil) {
        guard let item = imageManager.currentItem else { return }

        isLoading = true

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.loadImage(from: item.url)

            // Reset modification flag for new image
            self.annotationModified = false

            // Clear undo/redo stacks for new image
            self.undoStack.removeAll()
            self.redoStack.removeAll()

            // Reset line selection to first line (right pupil vertical)
            self.selectedLineType = .rightPupilVertical

            // Fit image to view after loading (preserve scale during navigation)
            if let scale = preservingScale {
                self.applyScaleCentered(scale)
            } else {
                self.resetView()
            }

            // Load or create annotation for this image
            self.loadOrCreateAnnotation(for: item.fileName)

            // Save last viewed image name for resume
            UserDefaults.standard.set(item.fileName, forKey: Self.lastImageNameKey)

            self.isLoading = false
        }
    }

    // MARK: - Line Position Management

    /// Get the position for a specific line type (normalized 0-1)
    func getLinePosition(for lineType: BlinkLineType) -> CGFloat {
        return currentAnnotation?.getLinePosition(for: lineType) ?? 0.5
    }

    /// Set the position for a specific line type (normalized 0-1)
    func setLinePosition(for lineType: BlinkLineType, value: CGFloat) {
        guard var annotation = currentAnnotation,
              let imageName = currentImageName else { return }
        annotation.setLinePosition(for: lineType, value: value)
        currentAnnotation = annotation
        annotations[imageName] = annotation
        annotationModified = true
    }

    /// Check if a line is visible
    func isLineVisible(_ lineType: BlinkLineType) -> Bool {
        return currentAnnotation?.isLineVisible(lineType) ?? true
    }

    /// Toggle line visibility
    func toggleLineVisibility(_ lineType: BlinkLineType) {
        guard var annotation = currentAnnotation,
              let imageName = currentImageName else { return }
        annotation.visibility.toggle(lineType)
        currentAnnotation = annotation
        annotations[imageName] = annotation
    }

    /// Set line visibility
    func setLineVisibility(_ lineType: BlinkLineType, visible: Bool) {
        guard var annotation = currentAnnotation,
              let imageName = currentImageName else { return }
        annotation.visibility.setVisible(lineType, visible: visible)
        currentAnnotation = annotation
        annotations[imageName] = annotation
    }

    // MARK: - Line Position Nudge (Arrow Keys)

    /// Nudge step: 1px in normalized coordinates based on image height
    private var nudgeStep: CGFloat {
        let imageHeight = renderer?.textureManager.imageSize.height ?? 1000
        return imageHeight > 0 ? 1.0 / imageHeight : 0.001
    }

    /// Nudge selected line position upward (decrease Y)
    /// Only applies to horizontal lines; vertical lines (which move left/right) are ignored
    func nudgeLineUp() {
        guard !selectedLineType.isVertical else { return }
        createAnnotationIfNeeded()
        guard currentAnnotation != nil else { return }

        pushUndoState()
        let current = getLinePosition(for: selectedLineType)
        let newPosition = max(0, current - nudgeStep)
        setLinePosition(for: selectedLineType, value: newPosition)
    }

    /// Nudge selected line position downward (increase Y)
    /// Only applies to horizontal lines; vertical lines (which move left/right) are ignored
    func nudgeLineDown() {
        guard !selectedLineType.isVertical else { return }
        createAnnotationIfNeeded()
        guard currentAnnotation != nil else { return }

        pushUndoState()
        let current = getLinePosition(for: selectedLineType)
        let newPosition = min(1, current + nudgeStep)
        setLinePosition(for: selectedLineType, value: newPosition)
    }

    // MARK: - Line Selection (A/Z Keys)

    /// Select the previous line type (wraps around)
    func selectPreviousLine() {
        let allLines = BlinkLineType.allCases
        guard let currentIndex = allLines.firstIndex(of: selectedLineType) else { return }

        let previousIndex = currentIndex == 0 ? allLines.count - 1 : currentIndex - 1
        selectedLineType = allLines[previousIndex]
    }

    /// Select the next line type (wraps around)
    func selectNextLine() {
        let allLines = BlinkLineType.allCases
        guard let currentIndex = allLines.firstIndex(of: selectedLineType) else { return }

        let nextIndex = (currentIndex + 1) % allLines.count
        selectedLineType = allLines[nextIndex]
    }

    // MARK: - Line Dragging

    /// Begin dragging the selected line
    func beginLineDrag(at point: CGPoint) {
        // Create annotation on first canvas interaction if not exists
        createAnnotationIfNeeded()

        guard currentAnnotation != nil else { return }

        isDraggingLine = true
        lastDragPoint = point

        // Store initial line position for relative dragging
        dragStartLinePosition = getLinePosition(for: selectedLineType)

        // Store initial touch point in normalized coordinates
        if let normalizedPoint = convertTouchToNormalized(point) {
            dragStartNormalizedPoint = normalizedPoint
        }

        // Push current state to undo stack
        pushUndoState()

        // Don't move line on initial touch - wait for drag movement
    }

    /// Continue dragging the selected line
    func continueLineDrag(to point: CGPoint) {
        guard isDraggingLine else { return }

        lastDragPoint = point
        updateLineFromRelativeDrag(point)
    }

    /// End line dragging
    func endLineDrag() {
        guard isDraggingLine else { return }

        isDraggingLine = false
        annotationModified = true
    }

    /// Convert touch point to normalized coordinates (0-1)
    private func convertTouchToNormalized(_ point: CGPoint) -> CGPoint? {
        guard let renderer = renderer else { return nil }

        let screenPoint = renderer.convertTouchToScreen(point)
        let imagePoint = renderer.canvasTransform.screenToImage(screenPoint)

        let imageSize = renderer.textureManager.imageSize
        guard imageSize.width > 0 && imageSize.height > 0 else { return nil }

        return CGPoint(
            x: imagePoint.x / imageSize.width,
            y: imagePoint.y / imageSize.height
        )
    }

    /// Update line position from drag point using relative movement
    private func updateLineFromRelativeDrag(_ point: CGPoint) {
        guard let currentNormalized = convertTouchToNormalized(point) else { return }

        // Calculate delta from drag start
        let deltaX = currentNormalized.x - dragStartNormalizedPoint.x
        let deltaY = currentNormalized.y - dragStartNormalizedPoint.y

        // Apply delta to initial position
        if selectedLineType.isVertical {
            // Vertical line: move by X delta
            let newPosition = dragStartLinePosition + deltaX
            let clampedPosition = max(0, min(1, newPosition))
            setLinePosition(for: selectedLineType, value: clampedPosition)
        } else {
            // Horizontal line: move by Y delta
            let newPosition = dragStartLinePosition + deltaY
            let clampedPosition = max(0, min(1, newPosition))
            setLinePosition(for: selectedLineType, value: clampedPosition)
        }
    }

    // MARK: - Annotation Inheritance

    /// Inherit annotation from previous frame (if exists)
    func inheritFromPreviousFrame() {
        print("[ApplyPrevious] Called - currentImageIndex: \(currentImageIndex)")

        guard currentImageIndex > 0 else {
            print("[ApplyPrevious] Failed: currentImageIndex <= 0")
            return
        }

        guard let currentName = currentImageName else {
            print("[ApplyPrevious] Failed: currentImageName is nil")
            return
        }

        print("[ApplyPrevious] currentName: \(currentName)")

        // Get previous image's name
        let previousIndex = currentImageIndex - 1
        guard previousIndex >= 0,
              previousIndex < imageManager.items.count else {
            print("[ApplyPrevious] Failed: previousIndex out of bounds")
            return
        }
        let previousName = imageManager.items[previousIndex].fileName
        print("[ApplyPrevious] previousName: \(previousName)")
        print("[ApplyPrevious] Available annotations: \(Array(annotations.keys))")

        if let previousAnnotation = annotations[previousName] {
            var newAnnotation = previousAnnotation
            newAnnotation.imageName = currentName
            currentAnnotation = newAnnotation
            annotations[currentName] = newAnnotation
            annotationModified = true
            print("[ApplyPrevious] ✅ Copied annotation from \(previousName) to \(currentName)")
        } else {
            print("[ApplyPrevious] ❌ No annotation found for previousName: \(previousName)")
        }
    }

    /// Load annotation for an image, auto-copying from previous if enabled
    ///
    /// Annotation loading behavior:
    /// 1. If existing annotation exists, use it
    /// 2. If auto-copy is ON and no annotation exists, copy from previous image
    /// 3. Otherwise, set currentAnnotation to nil (annotation created on first canvas click)
    private func loadOrCreateAnnotation(for imageName: String) {
        // Use existing annotation if available
        if let existing = annotations[imageName] {
            currentAnnotation = existing
            print("[Annotation] Loaded existing for \(imageName)")
            return
        }

        // No annotation exists - this is a "new" image
        // If auto-copy is enabled, copy from previous image immediately
        if autoCopyPreviousAnnotation {
            let previousIndex = currentImageIndex - 1
            if previousIndex >= 0 && previousIndex < imageManager.items.count {
                let previousName = imageManager.items[previousIndex].fileName
                if let previous = annotations[previousName] {
                    var inherited = previous
                    inherited.imageName = imageName
                    currentAnnotation = inherited
                    annotations[imageName] = inherited
                    print("[Annotation] Auto-copied from \(previousName) to \(imageName)")
                    return
                }
            }
        }

        // No annotation yet - will be created on first canvas interaction
        currentAnnotation = nil
        print("[Annotation] No annotation for \(imageName) (will create on click)")
    }

    /// Create annotation for current image (called on first canvas interaction)
    ///
    /// If auto-copy is ON, copies from previous image; otherwise creates default
    func createAnnotationIfNeeded() {
        guard currentAnnotation == nil,
              let imageName = currentImageName else { return }

        // Auto-copy from previous image (if enabled)
        if autoCopyPreviousAnnotation {
            let previousIndex = currentImageIndex - 1
            if previousIndex >= 0 && previousIndex < imageManager.items.count {
                let previousName = imageManager.items[previousIndex].fileName
                if let previous = annotations[previousName] {
                    var inherited = previous
                    inherited.imageName = imageName
                    currentAnnotation = inherited
                    annotations[imageName] = inherited
                    print("[Annotation] Created (auto-copied from \(previousName))")
                    return
                }
            }
        }

        // Create new default annotation
        currentAnnotation = BlinkAnnotation.defaultAnnotation(imageName: imageName)
        annotations[imageName] = currentAnnotation
        print("[Annotation] Created default for \(imageName)")
    }

    // MARK: - Navigation Gesture Handling

    func handlePan(translation: CGPoint) {
        let scaledTranslation = renderer?.convertTouchToScreen(translation) ?? translation
        renderer?.canvasTransform.applyPan(delta: scaledTranslation)
        transformVersion += 1
    }

    func handlePinchDelta(scale: CGFloat, at center: CGPoint) {
        let screenCenter = renderer?.convertTouchToScreen(center) ?? center
        renderer?.canvasTransform.applyPinch(scaleFactor: scale, center: screenCenter)
        currentScale = renderer?.canvasTransform.scale ?? 1.0
        transformVersion += 1
    }

    func handleRotationDelta(angle: CGFloat, at center: CGPoint) {
        let screenCenter = renderer?.convertTouchToScreen(center) ?? center
        renderer?.canvasTransform.applyRotation(angleDelta: angle, center: screenCenter)
        transformVersion += 1
    }

    /// Fit image to view (aspect fit, centered, original orientation)
    func resetView() {
        guard let renderer = renderer else { return }

        let imageSize = renderer.textureManager.imageSize
        let viewportSize = renderer.viewportSize

        renderer.canvasTransform.fitToView(imageSize: imageSize, viewSize: viewportSize)
        currentScale = renderer.canvasTransform.scale
        transformVersion += 1
        print("[View] Fit to view: scale=\(String(format: "%.2f", currentScale))")
    }

    /// Apply a specific scale while centering the image (used to preserve zoom during navigation)
    private func applyScaleCentered(_ scale: CGFloat) {
        guard let renderer = renderer else { return }

        let imageSize = renderer.textureManager.imageSize
        let viewportSize = renderer.viewportSize

        renderer.canvasTransform.centerWithScale(scale, imageSize: imageSize, viewSize: viewportSize)
        currentScale = renderer.canvasTransform.scale
        transformVersion += 1
        print("[View] Preserved scale: \(String(format: "%.2f", currentScale))")
    }

    // MARK: - Undo/Redo

    private func pushUndoState() {
        guard let current = currentAnnotation else { return }

        undoStack.append(current)
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst()
        }

        // Clear redo stack on new action
        redoStack.removeAll()
    }

    func undo() {
        guard let current = currentAnnotation,
              let imageName = currentImageName,
              !undoStack.isEmpty else { return }

        let previousState = undoStack.removeLast()
        redoStack.append(current)

        currentAnnotation = previousState
        annotations[imageName] = previousState
        annotationModified = true
    }

    func redo() {
        guard let current = currentAnnotation,
              let imageName = currentImageName,
              !redoStack.isEmpty else { return }

        let nextState = redoStack.removeLast()
        undoStack.append(current)

        currentAnnotation = nextState
        annotations[imageName] = nextState
        annotationModified = true
    }

    /// Clear all annotations for current image
    func clearAllAnnotations() {
        guard currentAnnotation != nil,
              let imageName = currentImageName else { return }

        pushUndoState()
        currentAnnotation = BlinkAnnotation.defaultAnnotation(imageName: imageName)
        annotations[imageName] = currentAnnotation
        annotationModified = true
        print("[Clear] Reset annotations to default")
    }

    /// Reset all data (images, annotations, JSON)
    func resetAll() {
        // Clear files on disk
        do {
            try ProjectFileService.shared.clearAllData()
            BlinkAnnotationLoader.shared.deleteAnnotations()
        } catch {
            print("[ResetAll] Failed to clear data: \(error)")
        }

        // Clear in-memory state
        imageManager.clear()
        annotations = [:]
        currentAnnotation = nil
        undoStack = []
        redoStack = []
        annotationModified = false

        // Reset display
        renderer?.clearImage()
        currentImageIndex = 0
        totalImageCount = 0
        transformVersion += 1

        print("[ResetAll] All data has been reset")
    }

    // MARK: - Save/Load

    /// Save current annotation (called on image navigation and app background)
    func saveBeforeBackground() {
        if annotationModified {
            saveCurrentAnnotation()
        }
        saveAllAnnotations()
        print("[Save] Background save completed")
    }

    private func saveCurrentAnnotation() {
        guard let annotation = currentAnnotation,
              let imageName = currentImageName else { return }
        annotations[imageName] = annotation
        annotationModified = false
    }

    /// Save all annotations to JSON file
    func saveAllAnnotations() {
        BlinkAnnotationLoader.shared.saveAnnotations(annotations)
    }

    /// Load all annotations from JSON file
    func loadAllAnnotations() {
        annotations = BlinkAnnotationLoader.shared.loadAnnotations()
        print("[Load] Loaded \(annotations.count) annotations")
    }
}
