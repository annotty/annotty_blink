import SwiftUI

/// Container view that combines MetalCanvasView with line annotation overlay
struct CanvasContainerView: View {
    @ObservedObject var viewModel: CanvasViewModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Metal canvas with UIKit touch handling
                if let renderer = viewModel.renderer {
                    MetalCanvasView(
                        renderer: renderer,
                        gestureCoordinator: viewModel.gestureCoordinator
                    )
                } else {
                    // Placeholder when no renderer
                    Rectangle()
                        .fill(Color(white: 0.2))
                        .overlay(
                            Text("No image loaded")
                                .foregroundColor(.gray)
                        )
                }

                // Line annotation overlay
                LineOverlayView(viewModel: viewModel)
                    .allowsHitTesting(false)

                // Selected line indicator badge
                VStack {
                    HStack {
                        Spacer()
                        selectedLineBadge
                            .padding(8)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)

                // Drag indicator (shows when actively dragging)
                if viewModel.isDraggingLine {
                    dragIndicator
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                viewModel.updateViewSize(geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                viewModel.updateViewSize(newSize)
            }
        }
    }

    /// Badge showing the currently selected line
    private var selectedLineBadge: some View {
        let lineType = viewModel.selectedLineType
        let eyeLabel = lineType.isLeftEye ? "L" : "R"

        return HStack(spacing: 4) {
            Circle()
                .fill(lineType.color)
                .frame(width: 10, height: 10)

            Text("\(eyeLabel): \(lineType.displayName)")
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.6))
        .cornerRadius(4)
    }

    /// Drag indicator showing line movement direction
    private var dragIndicator: some View {
        let lineType = viewModel.selectedLineType
        let direction = lineType.isVertical ? "↔" : "↕"

        return VStack {
            Spacer()
            HStack {
                Spacer()
                Text(direction)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(lineType.color)
                    .shadow(color: .black, radius: 2)
                Spacer()
            }
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    CanvasContainerView(viewModel: CanvasViewModel())
}
