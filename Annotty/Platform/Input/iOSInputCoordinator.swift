#if os(iOS)
import UIKit
import Combine

/// iOS implementation of input coordination using UIKit touch and gesture recognizers
/// Handles Apple Pencil, finger touch, and multi-finger gestures
class iOSInputCoordinator: NSObject, InputCoordinatorProtocol {

    // MARK: - InputCoordinatorProtocol Callbacks

    var onLineDragBegin: ((CGPoint) -> Void)?
    var onLineDragContinue: ((CGPoint) -> Void)?
    var onLineDragEnd: (() -> Void)?
    var onPan: ((CGPoint) -> Void)?
    var onPinch: ((CGFloat, CGPoint) -> Void)?
    var onRotation: ((CGFloat, CGPoint) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onSelectPreviousLine: (() -> Void)?  // Triggered via hardware keyboard shortcuts
    var onSelectNextLine: (() -> Void)?      // Triggered via hardware keyboard shortcuts
    var onPreviousImage: (() -> Void)?       // Triggered via hardware keyboard shortcuts
    var onNextImage: (() -> Void)?           // Triggered via hardware keyboard shortcuts

    // MARK: - State

    private(set) var isDraggingLine = false
    private var isPendingDrag = false
    private var pendingDragPoint: CGPoint = .zero
    private var pendingDragTimer: DispatchWorkItem?
    private var currentTouchCount = 0
    private var lastPinchScale: CGFloat = 1.0
    private var dragInputType: InputType = .finger

    /// Last time a navigation gesture (pinch/rotation) ended
    private var lastNavigationGestureTime: Date = .distantPast

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

        // Pan gesture (2 fingers for navigation, also accepts trackpad scroll)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.allowedScrollTypesMask = [.continuous]
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
        guard Date().timeIntervalSince(lastNavigationGestureTime) > InputConstants.lineDragCooldownPeriod else {
            return
        }

        guard let touch = touches.first else { return }
        let inputType = classifyTouch(touch)
        let location = touch.location(in: view)

        if inputType == .pencil {
            // Pencil: Start dragging immediately
            dragInputType = .pencil
            isDraggingLine = true
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
                guard Date().timeIntervalSince(self.lastNavigationGestureTime) > InputConstants.lineDragCooldownPeriod else {
                    self.isPendingDrag = false
                    return
                }
                self.isPendingDrag = false
                self.isDraggingLine = true
                self.onLineDragBegin?(self.pendingDragPoint)
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + InputConstants.fingerDrawingDelay,
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
        } else if isDraggingLine {
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
        } else if isDraggingLine {
            // Normal drag end
            isDraggingLine = false
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

        if isDraggingLine {
            isDraggingLine = false
            onLineDragEnd?()
        }
    }

    // MARK: - Gesture Handlers

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }

        switch gesture.state {
        case .changed:
            let translation = gesture.translation(in: view)
            
            // X/Y方向: パン（画像移動）
            // 2本指スワイプは常に移動として扱う（ズームはピンチで行う）
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
            guard Date().timeIntervalSince(lastNavigationGestureTime) > InputConstants.undoCooldownPeriod else {
                return
            }
            onUndo?()
        }
    }

    @objc private func handleThreeFingerTap(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .recognized {
            guard Date().timeIntervalSince(lastNavigationGestureTime) > InputConstants.undoCooldownPeriod else {
                return
            }
            onRedo?()
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension iOSInputCoordinator: UIGestureRecognizerDelegate {
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
#endif
