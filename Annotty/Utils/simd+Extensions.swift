import simd
import CoreGraphics

#if os(iOS)
import UIKit
typealias PlatformColorSIMD = UIColor
#elseif os(macOS)
import AppKit
typealias PlatformColorSIMD = NSColor
#endif

extension simd_float2 {
    /// Create from CGPoint
    init(_ point: CGPoint) {
        self.init(Float(point.x), Float(point.y))
    }

    /// Convert to CGPoint
    var cgPoint: CGPoint {
        CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
}

extension simd_float4 {
    /// Create from PlatformColor (UIColor on iOS, NSColor on macOS)
    init(_ color: PlatformColorSIMD) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        #if os(iOS)
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif os(macOS)
        // Convert to RGB color space first for macOS
        if let rgbColor = color.usingColorSpace(.deviceRGB) {
            rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        }
        #endif

        self.init(Float(r), Float(g), Float(b), Float(a))
    }

    /// Red component
    var red: Float { x }

    /// Green component
    var green: Float { y }

    /// Blue component
    var blue: Float { z }

    /// Alpha component
    var alpha: Float { w }
}

extension simd_float3x3 {
    /// Identity matrix
    static var identity: simd_float3x3 {
        simd_float3x3(
            simd_float3(1, 0, 0),
            simd_float3(0, 1, 0),
            simd_float3(0, 0, 1)
        )
    }

    /// Create translation matrix
    static func translation(_ tx: Float, _ ty: Float) -> simd_float3x3 {
        simd_float3x3(
            simd_float3(1, 0, 0),
            simd_float3(0, 1, 0),
            simd_float3(tx, ty, 1)
        )
    }

    /// Create scale matrix
    static func scale(_ sx: Float, _ sy: Float) -> simd_float3x3 {
        simd_float3x3(
            simd_float3(sx, 0, 0),
            simd_float3(0, sy, 0),
            simd_float3(0, 0, 1)
        )
    }

    /// Create rotation matrix
    static func rotation(_ angle: Float) -> simd_float3x3 {
        let c = cos(angle)
        let s = sin(angle)

        return simd_float3x3(
            simd_float3(c, s, 0),
            simd_float3(-s, c, 0),
            simd_float3(0, 0, 1)
        )
    }
}
