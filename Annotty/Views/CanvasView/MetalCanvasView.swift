import SwiftUI
import MetalKit

// MARK: - iOS Implementation

#if os(iOS)
import UIKit

/// Custom MTKView subclass that handles touch events for drawing (iOS)
class TouchableMTKView: MTKView {
    /// Gesture coordinator for handling drawing vs navigation
    var gestureCoordinator: iOSInputCoordinator?

    /// Hardware keyboard commands for line/image navigation on iPad + Mac
    override var keyCommands: [UIKeyCommand]? {
        [
            // Line selection (up/down)
            UIKeyCommand(
                input: UIKeyCommand.inputUpArrow,
                modifierFlags: [],
                action: #selector(handleArrowKey(_:))
            ),
            UIKeyCommand(
                input: UIKeyCommand.inputDownArrow,
                modifierFlags: [],
                action: #selector(handleArrowKey(_:))
            ),
            // Image navigation (left/right)
            UIKeyCommand(
                input: UIKeyCommand.inputLeftArrow,
                modifierFlags: [],
                action: #selector(handleArrowKey(_:))
            ),
            UIKeyCommand(
                input: UIKeyCommand.inputRightArrow,
                modifierFlags: [],
                action: #selector(handleArrowKey(_:))
            ),
            // Alternative keys
            UIKeyCommand(
                input: "a",
                modifierFlags: [],
                action: #selector(handleArrowKey(_:))
            ),
            UIKeyCommand(
                input: "z",
                modifierFlags: [],
                action: #selector(handleArrowKey(_:))
            )
        ]
    }

    override var canBecomeFirstResponder: Bool { true }

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        isMultipleTouchEnabled = true
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            becomeFirstResponder()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        gestureCoordinator?.touchesBegan(touches, with: event, in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        gestureCoordinator?.touchesMoved(touches, with: event, in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        gestureCoordinator?.touchesEnded(touches, with: event, in: self)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        gestureCoordinator?.touchesCancelled(touches, with: event, in: self)
    }

    @objc private func handleArrowKey(_ command: UIKeyCommand) {
        guard let input = command.input else { return }

        // Check arrow keys first (don't lowercase special key constants)
        switch input {
        case UIKeyCommand.inputUpArrow:
            gestureCoordinator?.onSelectPreviousLine?()
        case UIKeyCommand.inputDownArrow:
            gestureCoordinator?.onSelectNextLine?()
        case UIKeyCommand.inputLeftArrow:
            gestureCoordinator?.onPreviousImage?()
        case UIKeyCommand.inputRightArrow:
            gestureCoordinator?.onNextImage?()
        default:
            // For letter keys, compare lowercased
            switch input.lowercased() {
            case "a":
                gestureCoordinator?.onSelectPreviousLine?()
            case "z":
                gestureCoordinator?.onSelectNextLine?()
            default:
                break
            }
        }
    }
}

/// SwiftUI wrapper for MTKView that renders the canvas with UIKit touch handling (iOS)
struct MetalCanvasView: UIViewRepresentable {
    @ObservedObject var renderer: MetalRenderer
    let gestureCoordinator: GestureCoordinator

    func makeUIView(context: Context) -> TouchableMTKView {
        let mtkView = TouchableMTKView(frame: .zero, device: renderer.device)
        mtkView.delegate = context.coordinator
        mtkView.clearColor = MTLClearColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false
        mtkView.preferredFramesPerSecond = 60

        // Connect gesture coordinator
        mtkView.gestureCoordinator = gestureCoordinator
        gestureCoordinator.setupGestures(for: mtkView)

        return mtkView
    }

    func updateUIView(_ uiView: TouchableMTKView, context: Context) {
        uiView.setNeedsDisplay()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer)
    }

    class Coordinator: NSObject, MTKViewDelegate {
        let renderer: MetalRenderer

        init(renderer: MetalRenderer) {
            self.renderer = renderer
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderer.updateViewportSize(size, scaleFactor: view.contentScaleFactor)
        }

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor else {
                return
            }

            renderer.render(to: drawable, with: renderPassDescriptor)
        }
    }
}

// MARK: - macOS Implementation

#elseif os(macOS)
import AppKit

/// Custom MTKView subclass that handles mouse events for drawing (macOS)
class MouseMTKView: MTKView {
    /// Input coordinator for handling drawing vs navigation
    var inputCoordinator: macOSInputCoordinator?

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        setupView()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        // Enable mouse tracking
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        return true
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        inputCoordinator?.mouseDown(at: point, with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        inputCoordinator?.mouseDragged(to: point, with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        inputCoordinator?.mouseUp(at: point, with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        inputCoordinator?.rightMouseDown(at: point, with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        inputCoordinator?.scrollWheel(with: event)
    }

    // MARK: - Keyboard Events

    /// Handle key down events directly when view is first responder
    /// This acts as a backup/standard path if the local monitor doesn't catch it
    override func keyDown(with event: NSEvent) {
        if let inputCoordinator = inputCoordinator,
           inputCoordinator.handleKeyDown(with: event) {
            // Event handled
            return
        }
        super.keyDown(with: event)
    }
}

/// SwiftUI wrapper for MTKView that renders the canvas with AppKit mouse handling (macOS)
struct MetalCanvasView: NSViewRepresentable {
    @ObservedObject var renderer: MetalRenderer
    let gestureCoordinator: GestureCoordinator

    func makeNSView(context: Context) -> MouseMTKView {
        let mtkView = MouseMTKView(frame: .zero, device: renderer.device)
        mtkView.delegate = context.coordinator
        mtkView.clearColor = MTLClearColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false

        // macOS defaults to 60fps but can be higher on ProMotion displays
        if #available(macOS 12.0, *) {
            mtkView.preferredFramesPerSecond = 120
        } else {
            mtkView.preferredFramesPerSecond = 60
        }

        // Connect input coordinator
        mtkView.inputCoordinator = gestureCoordinator
        gestureCoordinator.setupGestures(for: mtkView)

        return mtkView
    }

    func updateNSView(_ nsView: MouseMTKView, context: Context) {
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer)
    }

    class Coordinator: NSObject, MTKViewDelegate {
        let renderer: MetalRenderer

        init(renderer: MetalRenderer) {
            self.renderer = renderer
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // macOS uses window backing scale factor
            let scaleFactor = view.window?.backingScaleFactor ?? 2.0
            renderer.updateViewportSize(size, scaleFactor: scaleFactor)
        }

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor else {
                return
            }

            renderer.render(to: drawable, with: renderPassDescriptor)
        }
    }
}
#endif
