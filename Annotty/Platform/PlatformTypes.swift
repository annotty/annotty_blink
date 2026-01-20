import Foundation
import CoreGraphics

#if os(iOS)
import UIKit
public typealias PlatformColor = UIColor
public typealias PlatformImage = UIImage
public typealias PlatformView = UIView
public typealias PlatformApplication = UIApplication
#elseif os(macOS)
import AppKit
public typealias PlatformColor = NSColor
public typealias PlatformImage = NSImage
public typealias PlatformView = NSView
public typealias PlatformApplication = NSApplication
#endif

// MARK: - Cross-Platform Image Extensions

extension PlatformImage {
    /// Load image from file path (cross-platform)
    static func loadFromFile(_ path: String) -> PlatformImage? {
        #if os(iOS)
        return UIImage(contentsOfFile: path)
        #elseif os(macOS)
        return NSImage(contentsOfFile: path)
        #endif
    }

    /// Get CGImage representation
    var platformCGImage: CGImage? {
        #if os(iOS)
        return cgImage
        #elseif os(macOS)
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }

    /// Create from CGImage
    static func fromCGImage(_ cgImage: CGImage) -> PlatformImage {
        #if os(iOS)
        return UIImage(cgImage: cgImage)
        #elseif os(macOS)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
    }

    /// Get PNG data representation
    func platformPNGData() -> Data? {
        #if os(iOS)
        return pngData()
        #elseif os(macOS)
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
        #endif
    }
}

// MARK: - Cross-Platform Color Extensions

extension PlatformColor {
    /// Get CGColor representation (consistent API)
    var platformCGColor: CGColor {
        return cgColor
    }

    #if os(macOS)
    /// Secondary system background color (macOS only - iOS already has this)
    static var secondarySystemBackground: PlatformColor {
        return NSColor.controlBackgroundColor
    }

    /// System background color (macOS only - iOS already has this)
    static var systemBackground: PlatformColor {
        return NSColor.windowBackgroundColor
    }
    #endif
}

// MARK: - App Lifecycle Notifications

struct PlatformNotifications {
    /// Notification for app going to background/resigning active
    static var willResignActive: Notification.Name {
        #if os(iOS)
        return UIApplication.willResignActiveNotification
        #elseif os(macOS)
        return NSApplication.willResignActiveNotification
        #endif
    }

    /// Notification for app becoming active
    static var didBecomeActive: Notification.Name {
        #if os(iOS)
        return UIApplication.didBecomeActiveNotification
        #elseif os(macOS)
        return NSApplication.didBecomeActiveNotification
        #endif
    }
}
