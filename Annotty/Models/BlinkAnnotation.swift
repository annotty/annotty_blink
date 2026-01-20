import SwiftUI

/// Represents a complete blink annotation for a single image
/// Contains positions for 12 annotation lines (6 per eye)
///
/// JSON format outputs `null` for hidden lines (not included in training data)
/// The `visibility` field is internal-only and not serialized
struct BlinkAnnotation: Equatable {
    var leftEye: EyeLinePositions
    var rightEye: EyeLinePositions
    var visibility: LineVisibility  // Internal only - not serialized to JSON
    /// Image filename (without extension) - used as the unique identifier
    var imageName: String

    /// Create default annotation with centered positions
    static func defaultAnnotation(imageName: String) -> BlinkAnnotation {
        BlinkAnnotation(
            leftEye: EyeLinePositions.defaultLeft(),
            rightEye: EyeLinePositions.defaultRight(),
            visibility: LineVisibility(),
            imageName: imageName
        )
    }

    // MARK: - Custom Codable (null for hidden lines)

    private enum CodingKeys: String, CodingKey {
        case leftEye, rightEye, imageName
        // visibility is excluded from JSON
    }

    /// Intermediate struct for encoding eye positions with null support
    private struct EncodableEyePositions: Encodable {
        let pupilVerticalX: CGFloat?
        let pupilHorizontalY: CGFloat?
        let upperBrowY: CGFloat?
        let lowerBrowY: CGFloat?
        let upperLidY: CGFloat?
        let lowerLidY: CGFloat?
    }

    /// Intermediate struct for decoding eye positions with null support
    private struct DecodableEyePositions: Decodable {
        let pupilVerticalX: CGFloat?
        let pupilHorizontalY: CGFloat?
        let upperBrowY: CGFloat?
        let lowerBrowY: CGFloat?
        let upperLidY: CGFloat?
        let lowerLidY: CGFloat?
    }

    /// Get position value for a specific line type (normalized 0-1)
    func getLinePosition(for lineType: BlinkLineType) -> CGFloat {
        switch lineType {
        case .leftPupilVertical:
            return leftEye.pupilVerticalX
        case .leftPupilHorizontal:
            return leftEye.pupilHorizontalY
        case .leftUpperBrow:
            return leftEye.upperBrowY
        case .leftLowerBrow:
            return leftEye.lowerBrowY
        case .leftUpperLid:
            return leftEye.upperLidY
        case .leftLowerLid:
            return leftEye.lowerLidY
        case .rightPupilVertical:
            return rightEye.pupilVerticalX
        case .rightPupilHorizontal:
            return rightEye.pupilHorizontalY
        case .rightUpperBrow:
            return rightEye.upperBrowY
        case .rightLowerBrow:
            return rightEye.lowerBrowY
        case .rightUpperLid:
            return rightEye.upperLidY
        case .rightLowerLid:
            return rightEye.lowerLidY
        }
    }

    /// Set position value for a specific line type (normalized 0-1)
    mutating func setLinePosition(for lineType: BlinkLineType, value: CGFloat) {
        let clampedValue = max(0, min(1, value))

        switch lineType {
        case .leftPupilVertical:
            leftEye.pupilVerticalX = clampedValue
        case .leftPupilHorizontal:
            leftEye.pupilHorizontalY = clampedValue
        case .leftUpperBrow:
            leftEye.upperBrowY = clampedValue
        case .leftLowerBrow:
            leftEye.lowerBrowY = clampedValue
        case .leftUpperLid:
            leftEye.upperLidY = clampedValue
        case .leftLowerLid:
            leftEye.lowerLidY = clampedValue
        case .rightPupilVertical:
            rightEye.pupilVerticalX = clampedValue
        case .rightPupilHorizontal:
            rightEye.pupilHorizontalY = clampedValue
        case .rightUpperBrow:
            rightEye.upperBrowY = clampedValue
        case .rightLowerBrow:
            rightEye.lowerBrowY = clampedValue
        case .rightUpperLid:
            rightEye.upperLidY = clampedValue
        case .rightLowerLid:
            rightEye.lowerLidY = clampedValue
        }
    }

    /// Check if a line is visible
    func isLineVisible(_ lineType: BlinkLineType) -> Bool {
        return visibility.isVisible(lineType)
    }
}

// MARK: - Codable Conformance

extension BlinkAnnotation: Codable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(imageName, forKey: .imageName)

        // Encode left eye with visibility-based null values
        let leftEncodable = EncodableEyePositions(
            pupilVerticalX: visibility.isVisible(.leftPupilVertical) ? leftEye.pupilVerticalX : nil,
            pupilHorizontalY: visibility.isVisible(.leftPupilHorizontal) ? leftEye.pupilHorizontalY : nil,
            upperBrowY: visibility.isVisible(.leftUpperBrow) ? leftEye.upperBrowY : nil,
            lowerBrowY: visibility.isVisible(.leftLowerBrow) ? leftEye.lowerBrowY : nil,
            upperLidY: visibility.isVisible(.leftUpperLid) ? leftEye.upperLidY : nil,
            lowerLidY: visibility.isVisible(.leftLowerLid) ? leftEye.lowerLidY : nil
        )
        try container.encode(leftEncodable, forKey: .leftEye)

        // Encode right eye with visibility-based null values
        let rightEncodable = EncodableEyePositions(
            pupilVerticalX: visibility.isVisible(.rightPupilVertical) ? rightEye.pupilVerticalX : nil,
            pupilHorizontalY: visibility.isVisible(.rightPupilHorizontal) ? rightEye.pupilHorizontalY : nil,
            upperBrowY: visibility.isVisible(.rightUpperBrow) ? rightEye.upperBrowY : nil,
            lowerBrowY: visibility.isVisible(.rightLowerBrow) ? rightEye.lowerBrowY : nil,
            upperLidY: visibility.isVisible(.rightUpperLid) ? rightEye.upperLidY : nil,
            lowerLidY: visibility.isVisible(.rightLowerLid) ? rightEye.lowerLidY : nil
        )
        try container.encode(rightEncodable, forKey: .rightEye)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imageName = try container.decode(String.self, forKey: .imageName)

        // Decode left eye (null values become default positions)
        let leftDecoded = try container.decode(DecodableEyePositions.self, forKey: .leftEye)
        let defaultLeft = EyeLinePositions.defaultLeft()
        leftEye = EyeLinePositions(
            pupilVerticalX: leftDecoded.pupilVerticalX ?? defaultLeft.pupilVerticalX,
            pupilHorizontalY: leftDecoded.pupilHorizontalY ?? defaultLeft.pupilHorizontalY,
            upperBrowY: leftDecoded.upperBrowY ?? defaultLeft.upperBrowY,
            lowerBrowY: leftDecoded.lowerBrowY ?? defaultLeft.lowerBrowY,
            upperLidY: leftDecoded.upperLidY ?? defaultLeft.upperLidY,
            lowerLidY: leftDecoded.lowerLidY ?? defaultLeft.lowerLidY
        )

        // Decode right eye (null values become default positions)
        let rightDecoded = try container.decode(DecodableEyePositions.self, forKey: .rightEye)
        let defaultRight = EyeLinePositions.defaultRight()
        rightEye = EyeLinePositions(
            pupilVerticalX: rightDecoded.pupilVerticalX ?? defaultRight.pupilVerticalX,
            pupilHorizontalY: rightDecoded.pupilHorizontalY ?? defaultRight.pupilHorizontalY,
            upperBrowY: rightDecoded.upperBrowY ?? defaultRight.upperBrowY,
            lowerBrowY: rightDecoded.lowerBrowY ?? defaultRight.lowerBrowY,
            upperLidY: rightDecoded.upperLidY ?? defaultRight.upperLidY,
            lowerLidY: rightDecoded.lowerLidY ?? defaultRight.lowerLidY
        )

        // Restore visibility from null values (null = hidden)
        visibility = LineVisibility()
        if leftDecoded.pupilVerticalX == nil { visibility.setVisible(.leftPupilVertical, visible: false) }
        if leftDecoded.pupilHorizontalY == nil { visibility.setVisible(.leftPupilHorizontal, visible: false) }
        if leftDecoded.upperBrowY == nil { visibility.setVisible(.leftUpperBrow, visible: false) }
        if leftDecoded.lowerBrowY == nil { visibility.setVisible(.leftLowerBrow, visible: false) }
        if leftDecoded.upperLidY == nil { visibility.setVisible(.leftUpperLid, visible: false) }
        if leftDecoded.lowerLidY == nil { visibility.setVisible(.leftLowerLid, visible: false) }
        if rightDecoded.pupilVerticalX == nil { visibility.setVisible(.rightPupilVertical, visible: false) }
        if rightDecoded.pupilHorizontalY == nil { visibility.setVisible(.rightPupilHorizontal, visible: false) }
        if rightDecoded.upperBrowY == nil { visibility.setVisible(.rightUpperBrow, visible: false) }
        if rightDecoded.lowerBrowY == nil { visibility.setVisible(.rightLowerBrow, visible: false) }
        if rightDecoded.upperLidY == nil { visibility.setVisible(.rightUpperLid, visible: false) }
        if rightDecoded.lowerLidY == nil { visibility.setVisible(.rightLowerLid, visible: false) }
    }
}

/// Positions for all 6 lines of a single eye
/// All values are normalized (0-1) relative to image dimensions
struct EyeLinePositions: Codable, Equatable {
    /// X coordinate for the vertical pupil center line (0-1)
    var pupilVerticalX: CGFloat
    /// Y coordinate for the horizontal pupil center line (0-1)
    var pupilHorizontalY: CGFloat
    /// Y coordinate for upper brow edge line (0-1)
    var upperBrowY: CGFloat
    /// Y coordinate for lower brow edge line (0-1)
    var lowerBrowY: CGFloat
    /// Y coordinate for upper eyelid line (0-1)
    var upperLidY: CGFloat
    /// Y coordinate for lower eyelid line (0-1)
    var lowerLidY: CGFloat

    /// Default positions for left eye (right side of image when viewing face)
    static func defaultLeft() -> EyeLinePositions {
        EyeLinePositions(
            pupilVerticalX: 0.7,      // Right side of image (subject's left eye)
            pupilHorizontalY: 0.5,    // Center vertically
            upperBrowY: 0.35,         // Above pupil
            lowerBrowY: 0.40,         // Below upper brow
            upperLidY: 0.45,          // Below brow, above pupil
            lowerLidY: 0.55           // Below pupil
        )
    }

    /// Default positions for right eye (left side of image when viewing face)
    static func defaultRight() -> EyeLinePositions {
        EyeLinePositions(
            pupilVerticalX: 0.3,      // Left side of image (subject's right eye)
            pupilHorizontalY: 0.5,    // Center vertically
            upperBrowY: 0.35,         // Above pupil
            lowerBrowY: 0.40,         // Below upper brow
            upperLidY: 0.45,          // Below brow, above pupil
            lowerLidY: 0.55           // Below pupil
        )
    }
}

/// Visibility state for all 12 lines
struct LineVisibility: Codable, Equatable {
    private var visibleLines: Set<Int>

    init() {
        // All lines visible by default
        visibleLines = Set(BlinkLineType.allCases.map { $0.rawValue })
    }

    func isVisible(_ lineType: BlinkLineType) -> Bool {
        return visibleLines.contains(lineType.rawValue)
    }

    mutating func setVisible(_ lineType: BlinkLineType, visible: Bool) {
        if visible {
            visibleLines.insert(lineType.rawValue)
        } else {
            visibleLines.remove(lineType.rawValue)
        }
    }

    mutating func toggle(_ lineType: BlinkLineType) {
        if visibleLines.contains(lineType.rawValue) {
            visibleLines.remove(lineType.rawValue)
        } else {
            visibleLines.insert(lineType.rawValue)
        }
    }
}

/// The 12 line types for blink annotation
enum BlinkLineType: Int, CaseIterable, Identifiable, Codable {
    // Left eye lines (0-5)
    case leftPupilVertical = 0
    case leftPupilHorizontal = 1
    case leftUpperBrow = 2
    case leftLowerBrow = 3
    case leftUpperLid = 4
    case leftLowerLid = 5

    // Right eye lines (6-11)
    case rightPupilVertical = 6
    case rightPupilHorizontal = 7
    case rightUpperBrow = 8
    case rightLowerBrow = 9
    case rightUpperLid = 10
    case rightLowerLid = 11

    var id: Int { rawValue }

    /// Whether this is a vertical line (moves horizontally)
    var isVertical: Bool {
        switch self {
        case .leftPupilVertical, .rightPupilVertical:
            return true
        default:
            return false
        }
    }

    /// Whether this line belongs to the left eye
    var isLeftEye: Bool {
        return rawValue <= 5
    }

    /// Display name for the line
    var displayName: String {
        switch self {
        case .leftPupilVertical: return "瞳孔垂直"
        case .leftPupilHorizontal: return "瞳孔水平"
        case .leftUpperBrow: return "眉毛上端"
        case .leftLowerBrow: return "眉毛下端"
        case .leftUpperLid: return "上眼瞼"
        case .leftLowerLid: return "下眼瞼"
        case .rightPupilVertical: return "瞳孔垂直"
        case .rightPupilHorizontal: return "瞳孔水平"
        case .rightUpperBrow: return "眉毛上端"
        case .rightLowerBrow: return "眉毛下端"
        case .rightUpperLid: return "上眼瞼"
        case .rightLowerLid: return "下眼瞼"
        }
    }

    /// Color for this line type
    var color: Color {
        switch self {
        case .leftPupilVertical: return Color.red
        case .leftPupilHorizontal: return Color.orange
        case .leftUpperBrow: return Color.yellow
        case .leftLowerBrow: return Color.green
        case .leftUpperLid: return Color.cyan
        case .leftLowerLid: return Color.blue
        case .rightPupilVertical: return Color(red: 1.0, green: 0, blue: 1.0) // Magenta
        case .rightPupilHorizontal: return Color.purple
        case .rightUpperBrow: return Color.pink
        case .rightLowerBrow: return Color(red: 0.5, green: 0.5, blue: 0) // Olive
        case .rightUpperLid: return Color(red: 0, green: 0.5, blue: 0.5) // Teal
        case .rightLowerLid: return Color.brown
        }
    }

    /// RGB values for export (0-255)
    var rgbColor: (r: UInt8, g: UInt8, b: UInt8) {
        switch self {
        case .leftPupilVertical: return (255, 0, 0)       // Red
        case .leftPupilHorizontal: return (255, 128, 0)   // Orange
        case .leftUpperBrow: return (255, 255, 0)         // Yellow
        case .leftLowerBrow: return (0, 255, 0)           // Green
        case .leftUpperLid: return (0, 255, 255)          // Cyan
        case .leftLowerLid: return (0, 0, 255)            // Blue
        case .rightPupilVertical: return (255, 0, 255)    // Magenta
        case .rightPupilHorizontal: return (128, 0, 255)  // Purple
        case .rightUpperBrow: return (255, 102, 178)      // Pink
        case .rightLowerBrow: return (128, 128, 0)        // Olive
        case .rightUpperLid: return (0, 128, 128)         // Teal
        case .rightLowerLid: return (139, 69, 19)         // Brown
        }
    }

    /// All lines for left eye
    static var leftEyeLines: [BlinkLineType] {
        [.leftPupilVertical, .leftPupilHorizontal, .leftUpperBrow, .leftLowerBrow, .leftUpperLid, .leftLowerLid]
    }

    /// All lines for right eye
    static var rightEyeLines: [BlinkLineType] {
        [.rightPupilVertical, .rightPupilHorizontal, .rightUpperBrow, .rightLowerBrow, .rightUpperLid, .rightLowerLid]
    }

    /// The vertical line for the same eye (for linked movement)
    var verticalLineForEye: BlinkLineType {
        return isLeftEye ? .leftPupilVertical : .rightPupilVertical
    }
}

/// Width of horizontal lines in pixels (extends from vertical line)
let horizontalLineHalfWidth: CGFloat = 10.0
