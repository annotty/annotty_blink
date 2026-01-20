import Foundation
import CoreGraphics

/// Input type classification
enum InputType {
    case pencil      // Apple Pencil (iOS only)
    case finger      // Touch (iOS) or mouse (macOS)
    case trackpad    // Trackpad gestures (macOS)
}

/// Protocol defining the input handling interface for canvas interactions
/// Both iOS (touch/pencil) and macOS (mouse/trackpad) implementations conform to this
protocol InputCoordinatorProtocol: AnyObject {

    // MARK: - Line Dragging Callbacks

    /// Called when line drag begins at a point
    var onLineDragBegin: ((CGPoint) -> Void)? { get set }

    /// Called when line drag continues to a point
    var onLineDragContinue: ((CGPoint) -> Void)? { get set }

    /// Called when line drag ends
    var onLineDragEnd: (() -> Void)? { get set }

    // MARK: - Navigation Callbacks

    /// Called when pan gesture updates with translation delta
    var onPan: ((CGPoint) -> Void)? { get set }

    /// Called when pinch/zoom gesture updates with scale and center point
    var onPinch: ((CGFloat, CGPoint) -> Void)? { get set }

    /// Called when rotation gesture updates with angle (radians) and center point
    var onRotation: ((CGFloat, CGPoint) -> Void)? { get set }

    // MARK: - Action Callbacks

    /// Called when undo action triggered
    var onUndo: (() -> Void)? { get set }

    /// Called when redo action triggered
    var onRedo: (() -> Void)? { get set }

    // MARK: - Selection Callbacks

    /// Called when up arrow pressed to select previous line
    var onSelectPreviousLine: (() -> Void)? { get set }

    /// Called when down arrow pressed to select next line
    var onSelectNextLine: (() -> Void)? { get set }

    // MARK: - Image Navigation Callbacks

    /// Called when left arrow pressed to go to previous image
    var onPreviousImage: (() -> Void)? { get set }

    /// Called when right arrow pressed to go to next image
    var onNextImage: (() -> Void)? { get set }

    // MARK: - State

    /// Whether a line drag is currently in progress
    var isDraggingLine: Bool { get }
}

// MARK: - Common Constants

/// Shared constants for input handling across platforms
struct InputConstants {
    /// Cooldown period after navigation gestures before allowing line dragging
    static let lineDragCooldownPeriod: TimeInterval = 0.2

    /// Cooldown period after navigation gestures before allowing undo/redo
    static let undoCooldownPeriod: TimeInterval = 0.3

    /// Delay before finger drawing starts on iOS (allows time to detect 2nd finger)
    static let fingerDrawingDelay: TimeInterval = 0.032  // 32ms
}
