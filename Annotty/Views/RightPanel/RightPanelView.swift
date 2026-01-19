import SwiftUI

/// Right panel with line selection for blink annotation
struct RightPanelView: View {
    @ObservedObject var viewModel: CanvasViewModel
    let onSettingsTapped: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Title
                Text("Lines")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.top, 12)

                // Right eye section (top - appears first in image from viewer's perspective)
                eyeSection(
                    title: "Right Eye",
                    lines: BlinkLineType.rightEyeLines,
                    isExpanded: true
                )

                // Left eye section
                eyeSection(
                    title: "Left Eye",
                    lines: BlinkLineType.leftEyeLines,
                    isExpanded: true
                )

                Divider()
                    .background(Color.gray)
                    .padding(.vertical, 8)

                // Settings button
                Button(action: onSettingsTapped) {
                    VStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title2)
                        Text("Settings")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color(white: 0.25))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)

                Spacer()
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(white: 0.1))
    }

    /// Section for one eye's lines
    @ViewBuilder
    private func eyeSection(title: String, lines: [BlinkLineType], isExpanded: Bool) -> some View {
        VStack(spacing: 4) {
            // Section header
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)

            // Line list
            ForEach(lines) { lineType in
                lineRow(lineType: lineType)
            }
        }
    }

    /// Single line row with selection and visibility toggle
    private func lineRow(lineType: BlinkLineType) -> some View {
        let isSelected = viewModel.selectedLineType == lineType
        let isVisible = viewModel.isLineVisible(lineType)

        return HStack(spacing: 8) {
            // Selection indicator
            Circle()
                .fill(isSelected ? lineType.color : Color.clear)
                .overlay(
                    Circle()
                        .stroke(lineType.color, lineWidth: 2)
                )
                .frame(width: 16, height: 16)

            // Line name
            Text(lineType.displayName)
                .font(.caption)
                .foregroundColor(isSelected ? .white : .gray)
                .lineLimit(1)

            Spacer()

            // Visibility toggle
            Button(action: {
                viewModel.toggleLineVisibility(lineType)
            }) {
                Image(systemName: isVisible ? "eye.fill" : "eye.slash")
                    .font(.caption)
                    .foregroundColor(isVisible ? .white : .gray.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? lineType.color.opacity(0.2) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedLineType = lineType
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Preview

#Preview {
    RightPanelView(
        viewModel: CanvasViewModel(),
        onSettingsTapped: {}
    )
    .frame(width: 120, height: 600)
}
