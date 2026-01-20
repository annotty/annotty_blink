import SwiftUI

/// Represents a complete blink annotation for a single image
/// Contains positions for 12 annotation lines (6 per eye)
struct BlinkAnnotation: Codable, Equatable {
    var leftEye: EyeLinePositions
    var rightEye: EyeLinePositions
    var visibility: LineVisibility
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
