import UIKit
import Combine

/// Input type classification
enum InputType {
    case pencil
    case finger
}

/// Gesture coordinator for blink annotation line dragging
/// - Pencil/Finger: Line dragging immediately
/// - 2+ fingers: Navigation (pan, zoom, rotate)
/// - 2-finger tap: Undo
/// - 3-finger tap: Redo
class GestureCoordinator: NSObject {
    // MARK: - Configuration

    /// Delay before finger drawing starts (allows time to detect 2nd finger)
    static let fingerDrawingDelay: TimeInterval = 0.032  // 32ms

    // MARK: - Callbacks

    /// Called when line drag begins
    var onLineDragBegin: ((CGPoint) -> Void)?

    /// Called when line drag continues
    var onLineDragContinue: ((CGPoint) -> Void)?

    /// Called when line drag ends
    var onLineDragEnd: (() -> Void)?

    /// Called when pan gesture updates
    var onPan: ((CGPoint) -> Void)?

    /// Called when pinch gesture updates
    var onPinch: ((CGFloat, CGPoint) -> Void)?

    /// Called when rotation gesture updates
    var onRotation: ((CGFloat, CGPoint) -> Void)?

    /// Called when undo triggered (2-finger tap)
    var onUndo: (() -> Void)?

    /// Called when redo triggered (3-finger tap)
    var onRedo: (() -> Void)?

    // MARK: - State

    private var isDragging = false
    private var isPendingDrag = false
    private var pendingDragPoint: CGPoint = .zero
    private var pendingDragTimer: DispatchWorkItem?
    private var currentTouchCount = 0
    private var lastPinchScale: CGFloat = 1.0
    private var dragInputType: InputType = .finger

    /// Last time a navigation gesture (pinch/rotation) ended
    private var lastNavigationGestureTime: Date = .distantPast

    /// Cooldown period after navigation gestures before allowing undo/redo
    private let undoCooldownPeriod: TimeInterval = 0.3

    /// Cooldown period after navigation gestures before allowing line dragging
    private let lineDragCooldownPeriod: TimeInterval = 0.2

    // MARK: - Gesture Recognizers

    private var panGesture: UIPanGestureRecognizer?
    private var pinchGesture: UIPinchGestureRecognizer?
    private var rotationGesture: UIRotationGestureRecognizer?
    private var twoFingerTapGesture: UITapGestureRecognizer?
    private var threeFingerTapGesture: UITapGestureRecognizer?

    // MARK: - Setup

    func setupGestures(for view: UIView) {
        // 2-finger tap (undo)
        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.numberOfTapsRequired = 1
        twoFingerTap.delegate = self
        view.addGestureRecognizer(twoFingerTap)
        twoFingerTapGesture = twoFingerTap

        // 3-finger tap (redo)
        let threeFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleThreeFingerTap(_:)))
        threeFingerTap.numberOfTouchesRequired = 3
        threeFingerTap.numberOfTapsRequired = 1
        threeFingerTap.delegate = self
        view.addGestureRecognizer(threeFingerTap)
        threeFingerTapGesture = threeFingerTap

        // Pan gesture (2 fingers for navigation)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        view.addGestureRecognizer(pan)
        panGesture = pan

        // Pinch gesture (zoom)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)
        pinchGesture = pinch

        // Rotation gesture (free rotation)
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        rotation.delegate = self
        view.addGestureRecognizer(rotation)
        rotationGesture = rotation
    }

    // MARK: - Touch Handling

    /// Classify touch input type
    func classifyTouch(_ touch: UITouch) -> InputType {
        switch touch.type {
        case .pencil:
            return .pencil
        case .direct, .indirect, .indirectPointer:
            return .finger
        @unknown default:
            return .finger
        }
    }

    /// Handle touch began
    func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?, in view: UIView) {
        currentTouchCount = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? touches.count

        // If 2+ fingers, cancel any pending/ongoing drag
        if currentTouchCount >= 2 {
            cancelPendingAndOngoingDrag()
            return
        }

        // Check cooldown after navigation gestures
        guard Date().timeIntervalSince(lastNavigationGestureTime) > lineDragCooldownPeriod else {
            return
        }

        guard let touch = touches.first else { return }
        let inputType = classifyTouch(touch)
        let location = touch.location(in: view)

        if inputType == .pencil {
            // Pencil: Start dragging immediately
            dragInputType = .pencil
            isDragging = true
            onLineDragBegin?(location)
        } else {
            // Finger: Wait 32ms before starting
            dragInputType = .finger
            isPendingDrag = true
            pendingDragPoint = location

            pendingDragTimer?.cancel()
            pendingDragTimer = DispatchWorkItem { [weak self] in
                guard let self = self, self.isPendingDrag else { return }
                // Re-check cooldown when timer fires
                guard Date().timeIntervalSince(self.lastNavigationGestureTime) > self.lineDragCooldownPeriod else {
                    self.isPendingDrag = false
                    return
                }
                self.isPendingDrag = false
                self.isDragging = true
                self.onLineDragBegin?(self.pendingDragPoint)
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.fingerDrawingDelay,
                execute: pendingDragTimer!
            )
        }
    }

    /// Handle touch moved
    func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?, in view: UIView) {
        currentTouchCount = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? touches.count

        // If 2+ fingers detected during dragging, cancel
        if currentTouchCount >= 2 {
            cancelPendingAndOngoingDrag()
            return
        }

        guard let touch = touches.first else { return }
        let location = touch.location(in: view)

        if isPendingDrag {
            // Still waiting for delay - update pending point
            pendingDragPoint = location
        } else if isDragging {
            // Already dragging - continue
            onLineDragContinue?(location)
        }
    }

    /// Handle touch ended
    func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?, in view: UIView) {
        let remainingTouches = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 0
        currentTouchCount = remainingTouches

        if isPendingDrag {
            // Touch ended before delay - cancel pending
            cancelPendingDrag()
        } else if isDragging {
            // Normal drag end
            isDragging = false
            onLineDragEnd?()
        }
    }

    /// Handle touch cancelled
    func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?, in view: UIView) {
        currentTouchCount = 0
        cancelPendingAndOngoingDrag()
    }

    // MARK: - Private Helpers

    /// Cancel pending drag timer (before 32ms)
    private func cancelPendingDrag() {
        pendingDragTimer?.cancel()
        pendingDragTimer = nil
        isPendingDrag = false
    }

    /// Cancel both pending and ongoing drags
    private func cancelPendingAndOngoingDrag() {
        cancelPendingDrag()

        if isDragging {
            isDragging = false
            onLineDragEnd?()
        }
    }

    // MARK: - Gesture Handlers

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }

        switch gesture.state {
        case .changed:
            let translation = gesture.translation(in: view)
            onPan?(translation)
            gesture.setTranslation(.zero, in: view)
        case .ended, .cancelled:
            lastNavigationGestureTime = Date()
        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let view = gesture.view else { return }

        switch gesture.state {
        case .began:
            lastPinchScale = 1.0
        case .changed:
            let center = gesture.location(in: view)
            let scale = gesture.scale / lastPinchScale
            onPinch?(scale, center)
            lastPinchScale = gesture.scale
        case .ended, .cancelled:
            lastPinchScale = 1.0
            lastNavigationGestureTime = Date()
        default:
            break
        }
    }

    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let view = gesture.view else { return }

        switch gesture.state {
        case .changed:
            let center = gesture.location(in: view)
            onRotation?(gesture.rotation, center)
            gesture.rotation = 0
        case .ended, .cancelled:
            lastNavigationGestureTime = Date()
        default:
            break
        }
    }

    @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .recognized {
            guard Date().timeIntervalSince(lastNavigationGestureTime) > undoCooldownPeriod else {
                return
            }
            onUndo?()
        }
    }

    @objc private func handleThreeFingerTap(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .recognized {
            guard Date().timeIntervalSince(lastNavigationGestureTime) > undoCooldownPeriod else {
                return
            }
            onRedo?()
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension GestureCoordinator: UIGestureRecognizerDelegate {
    /// Allow simultaneous gesture recognition for pan, pinch, and rotation
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let navigationGestures: [UIGestureRecognizer?] = [
            panGesture, pinchGesture, rotationGesture
        ]

        if navigationGestures.contains(where: { $0 === gestureRecognizer }) &&
           navigationGestures.contains(where: { $0 === otherGestureRecognizer }) {
            return true
        }

        let tapGestures: [UIGestureRecognizer?] = [
            twoFingerTapGesture, threeFingerTapGesture
        ]

        if tapGestures.contains(where: { $0 === gestureRecognizer }) ||
           tapGestures.contains(where: { $0 === otherGestureRecognizer }) {
            return true
        }

        return false
    }

    /// Ensure gestures only activate with finger touches, not pencil
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        return classifyTouch(touch) == .finger
    }
}
