import Foundation

// MARK: - Platform-Specific Input Coordinator Type Alias
//
// GestureCoordinator is a type alias that resolves to the appropriate
// platform-specific implementation:
// - iOS: iOSInputCoordinator (touch, Apple Pencil, multi-finger gestures)
// - macOS: macOSInputCoordinator (mouse, trackpad, keyboard shortcuts)
//
// This allows CanvasViewModel and other code to use "GestureCoordinator"
// without knowing which platform it's running on.

#if os(iOS)
/// iOS gesture coordinator using touch and Apple Pencil
typealias GestureCoordinator = iOSInputCoordinator
#elseif os(macOS)
/// macOS input coordinator using mouse and trackpad
typealias GestureCoordinator = macOSInputCoordinator
#endif
