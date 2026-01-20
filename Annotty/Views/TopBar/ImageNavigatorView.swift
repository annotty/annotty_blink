import SwiftUI

/// Image navigation controls (◀ 12/128 ▶ 🗑 ⬅)
struct ImageNavigatorView: View {
    let currentIndex: Int
    let totalCount: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    var onGoTo: ((Int) -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onApplyPrevious: (() -> Void)? = nil

    @State private var showingJumpPopover = false
    @State private var sliderValue: Double = 0
    @State private var showingDeleteConfirmation = false

    private var displayIndex: Int {
        totalCount > 0 ? currentIndex + 1 : 0
    }

    var body: some View {
        HStack(spacing: 16) {
            // Previous button
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(currentIndex > 0 ? .white : .gray)
            }
            .buttonStyle(.plain)
            .disabled(currentIndex <= 0)

            // Position indicator (tappable)
            Button(action: {
                sliderValue = Double(displayIndex)
                showingJumpPopover = true
            }) {
                HStack(spacing: 0) {
                    Text("\(displayIndex)")
                        .foregroundColor(.cyan)
                    Text("/\(totalCount)")
                        .foregroundColor(.white)
                }
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .frame(minWidth: 80)
            }
            .buttonStyle(.plain)
            .disabled(totalCount == 0)
            .popover(isPresented: $showingJumpPopover, arrowEdge: .bottom) {
                jumpPopoverContent
            }

            // Next button
            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .foregroundColor(currentIndex < totalCount - 1 ? .white : .gray)
            }
            .buttonStyle(.plain)
            .disabled(currentIndex >= totalCount - 1)

            // Delete button (if callback provided)
            if onDelete != nil {
                Divider()
                    .frame(height: 24)
                    .background(Color.gray.opacity(0.5))

                Button(action: {
                    showingDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .font(.title3)
                        .foregroundColor(totalCount > 0 ? .red.opacity(0.8) : .gray)
                }
                .buttonStyle(.plain)
                .disabled(totalCount == 0)
            }

            // Apply Previous button (copy annotation from previous image)
            if onApplyPrevious != nil {
                Divider()
                    .frame(height: 24)
                    .background(Color.gray.opacity(0.5))

                Button(action: {
                    onApplyPrevious?()
                }) {
                    Text("前の画像からコピー")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(currentIndex > 0 ? Color.cyan.opacity(0.8) : Color.gray.opacity(0.3))
                        .foregroundColor(currentIndex > 0 ? .white : .gray)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(currentIndex <= 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(white: 0.2))
        .cornerRadius(8)
        .alert("Delete Image?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("This will delete the image and its annotation data. This cannot be undone.")
        }
    }

    // MARK: - Jump Popover Content

    @ViewBuilder
    private var jumpPopoverContent: some View {
        VStack(spacing: 16) {
            // Current value display (left-aligned) + Go button
            HStack {
                // Large number on the left
                Text("\(Int(sliderValue))")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .frame(width: 80, alignment: .leading)

                Spacer()

                Button("Go") {
                    jumpToImage()
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }

            // Slider
            HStack {
                Text("1")
                    .font(.caption)
                    .foregroundColor(.gray)

                Slider(
                    value: $sliderValue,
                    in: 1...Double(max(1, totalCount)),
                    step: 1
                )
                .tint(.cyan)

                Text("\(totalCount)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(20)
        .frame(width: 280)
    }

    private func jumpToImage() {
        let targetIndex = Int(sliderValue) - 1  // Convert to 0-based index
        showingJumpPopover = false
        onGoTo?(targetIndex)
    }
}

// MARK: - Preview

#Preview {
    ImageNavigatorView(
        currentIndex: 11,
        totalCount: 128,
        onPrevious: {},
        onNext: {},
        onGoTo: { index in print("Go to: \(index)") },
        onDelete: { print("Delete") },
        onApplyPrevious: { print("Apply Previous") }
    )
    .background(Color(white: 0.1))
}

