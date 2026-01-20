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

    /// Current image name (filename without extension) - used as annotation key
    var currentImageName: String? {
        imageManager.currentItem?.baseName
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

    /// UserDefaults key for last viewed image
    private static let lastImageNameKey = "annotty.lastImageName"

    // MARK: - Initialization

    init() {
        print("🚀 CanvasViewModel init (Blink Annotation Mode)")
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
           let index = imageManager.items.firstIndex(where: { $0.baseName == lastImageName }) {
            imageManager.goTo(index: index)
            print("[Project] Resuming from: \(lastImageName)")
        }

        // Load current image with its annotation (if exists)
        if imageManager.currentItem != nil {
            loadCurrentImage()
        }
    }

    /// Import a single image to the project (appended at the end)
    func importImage(from sourceURL: URL) {
        // Save current annotations before import
        if annotationModified {
            saveCurrentAnnotation()
        }

        do {
            let destinationURL = try ProjectFileService.shared.copyImageToProject(sourceURL)
            print("[Import] Copied: \(destinationURL.lastPathComponent)")

            // Append to the end instead of reloading (which would sort alphabetically)
            imageManager.appendImages([destinationURL])

            // Navigate to the newly added image
            let newIndex = imageManager.items.count - 1
            imageManager.goTo(index: newIndex)
            loadCurrentImage()
        } catch {
            print("[Import] Failed: \(error)")
        }
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

    /// Delete the current image and its annotation
    func deleteCurrentImage() {
        guard let item = imageManager.currentItem else { return }

        let imageName = item.baseName

        // Save any unsaved annotation first
        if annotationModified {
            saveCurrentAnnotation()
        }

        do {
            // Delete the image file and associated files
            try ProjectFileService.shared.deleteImage(item.url)
            print("[Delete] Deleted image: \(item.baseName)")

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

        // Line selection callbacks (arrow keys)
        gestureCoordinator.onSelectPreviousLine = { [weak self] in
            self?.selectPreviousLine()
        }

        gestureCoordinator.onSelectNextLine = { [weak self] in
            self?.selectNextLine()
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

        // Navigate
        navigation()
        loadCurrentImage()
    }

    private func loadCurrentImage() {
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

            // Fit image to view after loading
            self.resetView()

            // Load or create annotation for this image
            self.loadOrCreateAnnotation(for: item.baseName)

            // Save last viewed image name for resume
            UserDefaults.standard.set(item.baseName, forKey: Self.lastImageNameKey)

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

    // MARK: - Line Selection (Arrow Keys)

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
        guard currentImageIndex > 0,
              let currentName = currentImageName else { return }

        // Get previous image's name
        let previousIndex = currentImageIndex - 1
        guard previousIndex >= 0,
              previousIndex < imageManager.items.count else { return }
        let previousName = imageManager.items[previousIndex].baseName

        if let previousAnnotation = annotations[previousName] {
            var newAnnotation = previousAnnotation
            newAnnotation.imageName = currentName
            currentAnnotation = newAnnotation
            annotations[currentName] = newAnnotation
            annotationModified = true
            print("[Inherit] Copied annotation from \(previousName)")
        }
    }

    /// Load or create annotation for an image
    private func loadOrCreateAnnotation(for imageName: String) {
        if let existing = annotations[imageName] {
            currentAnnotation = existing
        } else {
            // Try to inherit from previous frame
            let previousIndex = currentImageIndex - 1
            if previousIndex >= 0 && previousIndex < imageManager.items.count {
                let previousName = imageManager.items[previousIndex].baseName
                if let previous = annotations[previousName] {
                    var inherited = previous
                    inherited.imageName = imageName
                    currentAnnotation = inherited
                    annotations[imageName] = inherited
                    print("[Annotation] Inherited from \(previousName)")
                    return
                }
            }
            // Create new default annotation
            currentAnnotation = BlinkAnnotation.defaultAnnotation(imageName: imageName)
            annotations[imageName] = currentAnnotation
            print("[Annotation] Created new default for \(imageName)")
        }
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
