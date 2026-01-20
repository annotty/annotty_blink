#if os(iOS)
import UIKit
typealias PlatformColorLocal = UIColor
#elseif os(macOS)
import AppKit
typealias PlatformColorLocal = NSColor
#endif
import SwiftUI

extension PlatformColorLocal {
    /// Create PlatformColor from hex string
    convenience init(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if hexString.hasPrefix("#") {
            hexString.remove(at: hexString.startIndex)
        }

        var rgbValue: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgbValue)

        let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgbValue & 0x0000FF) / 255.0

        #if os(iOS)
        self.init(red: r, green: g, blue: b, alpha: 1.0)
        #elseif os(macOS)
        self.init(calibratedRed: r, green: g, blue: b, alpha: 1.0)
        #endif
    }

    /// Convert to hex string
    var hexString: String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0

        #if os(iOS)
        getRed(&r, green: &g, blue: &b, alpha: nil)
        #elseif os(macOS)
        // Convert to RGB color space first for macOS
        guard let rgbColor = usingColorSpace(.deviceRGB) else {
            return "#000000"
        }
        rgbColor.getRed(&r, green: &g, blue: &b, alpha: nil)
        #endif

        return String(format: "#%02X%02X%02X",
                      Int(r * 255),
                      Int(g * 255),
                      Int(b * 255))
    }

    /// Convert to UInt32 color key (for dictionary lookups)
    var colorKey: UInt32 {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0

        #if os(iOS)
        getRed(&r, green: &g, blue: &b, alpha: nil)
        #elseif os(macOS)
        guard let rgbColor = usingColorSpace(.deviceRGB) else {
            return 0
        }
        rgbColor.getRed(&r, green: &g, blue: &b, alpha: nil)
        #endif

        return UInt32(r * 255) << 16 | UInt32(g * 255) << 8 | UInt32(b * 255)
    }
}

extension Color {
    /// Create Color from hex string
    init(hex: String) {
        self.init(PlatformColorLocal(hex: hex))
    }
}
