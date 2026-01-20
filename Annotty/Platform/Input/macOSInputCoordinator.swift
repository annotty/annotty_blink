#if os(macOS)
import AppKit
import Combine

/// macOS implementation of input coordination using mouse and trackpad gestures
/// Handles mouse drag for lines, vertical scroll for zoom, horizontal scroll for pan, Option+scroll for rotation
class macOSInputCoordinator: NSObject, InputCoordinatorProtocol {

    // MARK: - InputCoordinatorProtocol Callbacks

    var onLineDragBegin: ((CGPoint) -> Void)?
    var onLineDragContinue: ((CGPoint) -> Void)?
    var onLineDragEnd: (() -> Void)?
    var onPan: ((CGPoint) -> Void)?
    var onPinch: ((CGFloat, CGPoint) -> Void)?
    var onRotation: ((CGFloat, CGPoint) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onSelectPreviousLine: (() -> Void)?
    var onSelectNextLine: (() -> Void)?
    var onPreviousImage: (() -> Void)?
    var onNextImage: (() -> Void)?

    // MARK: - State

    private(set) var isDraggingLine = false
    private var currentMouseLocation: CGPoint = .zero

    /// Last time a navigation gesture (pinch/rotation/scroll) ended
    private var lastNavigationGestureTime: Date = .distantPast

    /// Weak reference to the view for coordinate conversion
    private weak var view: NSView?

    // MARK: - Gesture Recognizers

    private var magnificationGesture: NSMagnificationGestureRecognizer?
    private var rotationGesture: NSRotationGestureRecognizer?

    // MARK: - Keyboard Event Monitor

    private var keyboardMonitor: Any?

    // MARK: - Setup

    /// Setup gesture recognizers for the view
    /// Note: Mouse events are handled via NSView override methods
    func setupGestures(for view: NSView) {
        self.view = view

        // Magnification gesture (trackpad pinch)
        let magnification = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
        magnification.delegate = self
        view.addGestureRecognizer(magnification)
        magnificationGesture = magnification

        // Rotation gesture (trackpad rotation)
        let rotation = NSRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        rotation.delegate = self
        view.addGestureRecognizer(rotation)
        rotationGesture = rotation

        // Keyboard event monitor for arrow keys
        setupKeyboardMonitor()
    }

    /// Setup keyboard event monitor at app level
    private func setupKeyboardMonitor() {
        // Remove any existing monitor first
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }

        print("[Input] Setting up keyboard monitor for arrow keys")
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            if self.handleKeyDown(with: event) {
                print("[Input] Key handled by monitor: Code \(event.keyCode)")
                return nil  // Consume the event (no beep)
            }
            return event  // Pass through unhandled events
        }
    }

    deinit {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Mouse Event Handling (called from NSView)

    /// Handle mouse down event
    func mouseDown(at point: CGPoint, with event: NSEvent) {
        currentMouseLocation = point

        // Check cooldown after navigation
        guard Date().timeIntervalSince(lastNavigationGestureTime) > InputConstants.lineDragCooldownPeriod else {
            return
        }

        // Mouse click starts dragging immediately (no delay like finger touch)
        isDraggingLine = true
        onLineDragBegin?(point)
    }

    /// Handle mouse dragged event
    func mouseDragged(to point: CGPoint, with event: NSEvent) {
        currentMouseLocation = point

        guard isDraggingLine else { return }
        onLineDragContinue?(point)
    }

    /// Handle mouse up event
    func mouseUp(at point: CGPoint, with event: NSEvent) {
        currentMouseLocation = point

        if isDraggingLine {
            isDraggingLine = false
            onLineDragEnd?()
        }
    }

    /// Handle scroll wheel event
    /// Default: Vertical scroll = Zoom, Horizontal scroll = Pan
    /// Option key: Rotation
    func scrollWheel(with event: NSEvent) {
        guard let view = view else { return }

        let location = view.convert(event.locationInWindow, from: nil)
        currentMouseLocation = location

        // Check for modifier keys
        let modifiers = event.modifierFlags

        if modifiers.contains(.option) {
            // Option + scroll = Rotation
            let rotationDelta = event.scrollingDeltaX * 0.01
            onRotation?(rotationDelta, location)
            lastNavigationGestureTime = Date()

        } else {
            // Default: Vertical = Zoom, Horizontal = Pan
            let deltaY = event.scrollingDeltaY
            let deltaX = event.scrollingDeltaX

            // Vertical scroll → Zoom (swipe up = zoom in, swipe down = zoom out)
            if abs(deltaY) > 0.1 {
                let zoomDelta = deltaY * 0.01
                let scale = 1.0 + zoomDelta
                onPinch?(scale, location)
            }

            // Horizontal scroll → Pan
            if abs(deltaX) > 0.1 {
                let translation = CGPoint(x: deltaX, y: 0)
                onPan?(translation)
            }

            lastNavigationGestureTime = Date()
        }
    }

    /// Handle right mouse down (context menu or alternative action)
    func rightMouseDown(at point: CGPoint, with event: NSEvent) {
        // Could be used for context menu or alternative actions
        // For now, do nothing
    }

    // MARK: - Keyboard Event Handling

    /// Handle key down event for shortcuts
    /// Returns true if the key was handled, false otherwise
    @discardableResult
    func handleKeyDown(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Cmd+Z = Undo, Cmd+Shift+Z = Redo
        if modifiers.contains(.command) && event.charactersIgnoringModifiers == "z" {
            if modifiers.contains(.shift) {
                onRedo?()
            } else {
                onUndo?()
            }
            return true
        }

        // Arrow keys for line selection (no command/option modifiers)
        if modifiers.contains(.command) || modifiers.contains(.option) {
            return false
        }

        switch event.keyCode {
        case 126: // Up arrow
            onSelectPreviousLine?()
            return true
        case 125: // Down arrow
            onSelectNextLine?()
            return true
        case 123: // Left arrow
            onPreviousImage?()
            return true
        case 124: // Right arrow
            onNextImage?()
            return true
        default:
            break
        }

        // Letter keys (A/Z) for the same navigation when arrows aren't convenient
        if let character = event.charactersIgnoringModifiers?.lowercased(), character.count == 1 {
            switch character {
            case "a":
                onSelectPreviousLine?()
                return true
            case "z":
                onSelectNextLine?()
                return true
            default:
                break
            }
        }

        return false
    }

    // MARK: - Gesture Handlers

    @objc private func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
        guard let view = gesture.view else { return }

        switch gesture.state {
        case .began, .changed:
            let center = gesture.location(in: view)
            // NSMagnificationGestureRecognizer.magnification is the scale change
            // magnification of 0 = no change, 1 = doubled, -0.5 = halved
            let scale = 1.0 + gesture.magnification
            onPinch?(scale, center)
            gesture.magnification = 0  // Reset for incremental changes

        case .ended, .cancelled:
            lastNavigationGestureTime = Date()

        default:
            break
        }
    }

    @objc private func handleRotation(_ gesture: NSRotationGestureRecognizer) {
        guard let view = gesture.view else { return }

        switch gesture.state {
        case .began, .changed:
            let center = gesture.location(in: view)
            // NSRotationGestureRecognizer.rotation is in radians
            onRotation?(gesture.rotation, center)
            gesture.rotation = 0  // Reset for incremental changes

        case .ended, .cancelled:
            lastNavigationGestureTime = Date()

        default:
            break
        }
    }
}

// MARK: - NSGestureRecognizerDelegate

extension macOSInputCoordinator: NSGestureRecognizerDelegate {
    /// Allow simultaneous gesture recognition
    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        // Allow magnification and rotation to work together
        let navigationGestures: [NSGestureRecognizer?] = [
            magnificationGesture, rotationGesture
        ]

        if navigationGestures.contains(where: { $0 === gestureRecognizer }) &&
           navigationGestures.contains(where: { $0 === otherGestureRecognizer }) {
            return true
        }

        return false
    }
}
#endif
