import SwiftUI

/// Overlay view that draws the 12 annotation lines on top of the canvas
struct LineOverlayView: View {
    @ObservedObject var viewModel: CanvasViewModel

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // Reference transformVersion to trigger re-render on transform changes
                let _ = viewModel.transformVersion

                guard let annotation = viewModel.currentAnnotation,
                      let renderer = viewModel.renderer else { return }

                let imageSize = renderer.textureManager.imageSize
                guard imageSize.width > 0 && imageSize.height > 0 else { return }

                // Draw all visible lines
                for lineType in BlinkLineType.allCases {
                    guard annotation.isLineVisible(lineType) else { continue }

                    let isSelected = lineType == viewModel.selectedLineType
                    drawLine(
                        context: context,
                        size: size,
                        lineType: lineType,
                        annotation: annotation,
                        renderer: renderer,
                        isSelected: isSelected
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Draw a single annotation line
    private func drawLine(
        context: GraphicsContext,
        size: CGSize,
        lineType: BlinkLineType,
        annotation: BlinkAnnotation,
        renderer: MetalRenderer,
        isSelected: Bool
    ) {
        let imageSize = renderer.textureManager.imageSize
        let position = annotation.getLinePosition(for: lineType)

        // Line styling
        let lineWidth: CGFloat = isSelected ? 3.0 : 1.5
        let color = lineType.color
        let strokeStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round)

        var path = Path()

        if lineType.isVertical {
            // Vertical line: spans full height
            let imageX = position * imageSize.width
            let imageY1: CGFloat = 0
            let imageY2: CGFloat = imageSize.height

            let screenPoint1 = imageToScreen(x: imageX, y: imageY1, renderer: renderer)
            let screenPoint2 = imageToScreen(x: imageX, y: imageY2, renderer: renderer)

            path.move(to: screenPoint1)
            path.addLine(to: screenPoint2)
        } else {
            // Horizontal line: short line centered on vertical line
            let verticalLine = lineType.verticalLineForEye
            let verticalX = annotation.getLinePosition(for: verticalLine)
            let imageY = position * imageSize.height

            // Half width in pixels (10 pixels on each side of vertical line)
            let halfWidthNormalized = horizontalLineHalfWidth / imageSize.width

            let imageX1 = (verticalX - halfWidthNormalized) * imageSize.width
            let imageX2 = (verticalX + halfWidthNormalized) * imageSize.width

            let screenPoint1 = imageToScreen(x: imageX1, y: imageY, renderer: renderer)
            let screenPoint2 = imageToScreen(x: imageX2, y: imageY, renderer: renderer)

            path.move(to: screenPoint1)
            path.addLine(to: screenPoint2)
        }

        // Draw the line
        context.stroke(path, with: .color(color), style: strokeStyle)

        // Draw selection indicator if selected
        if isSelected {
            // Draw a glow effect for selected line
            var glowStyle = strokeStyle
            glowStyle.lineWidth = lineWidth + 4
            context.stroke(path, with: .color(color.opacity(0.3)), style: glowStyle)
        }
    }

    /// Convert image coordinates to screen coordinates
    private func imageToScreen(x: CGFloat, y: CGFloat, renderer: MetalRenderer) -> CGPoint {
        let imagePoint = CGPoint(x: x, y: y)
        let screenPoint = renderer.canvasTransform.imageToScreen(imagePoint)
        // Convert from pixels back to points
        return CGPoint(
            x: screenPoint.x / renderer.contentScaleFactor,
            y: screenPoint.y / renderer.contentScaleFactor
        )
    }
}

// MARK: - Preview

#Preview {
    LineOverlayView(viewModel: CanvasViewModel())
        .background(Color.black)
}
