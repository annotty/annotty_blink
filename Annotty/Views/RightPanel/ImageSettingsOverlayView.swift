import SwiftUI

/// Slide-in overlay panel for image settings
/// Contains contrast and brightness adjustments, and annotation settings
struct ImageSettingsOverlayView: View {
    @Binding var isPresented: Bool
    @Binding var imageContrast: Float
    @Binding var imageBrightness: Float
    @Binding var autoCopyPreviousAnnotation: Bool
    var onAllReset: (() -> Void)? = nil

    @State private var showingAllResetConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            // Pass-through area (allows interaction with canvas)
            Color.clear
                .allowsHitTesting(false)

            // Settings panel
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Text("Settings")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isPresented = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    // Image section
                    VStack(spacing: 12) {
                        Text("Image")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)

                        SettingsSliderView(
                            title: "Contrast",
                            value: $imageContrast,
                            range: 0...2,
                            displayFormatter: { Int($0 * 100) },
                            displaySuffix: "%"
                        )

                        SettingsSliderView(
                            title: "Brightness",
                            value: $imageBrightness,
                            range: -1...1,
                            displayFormatter: { Int($0 * 100) },
                            displaySuffix: ""
                        )

                        // Reset button
                        Button(action: resetImageSettings) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset")
                            }
                            .font(.caption)
                            .foregroundColor(.cyan)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(Color(white: 0.2))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()
                        .background(Color.gray.opacity(0.5))
                        .padding(.horizontal, 16)

                    // Annotation settings section
                    VStack(spacing: 12) {
                        Text("Annotation")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)

                        // Auto-copy toggle
                        HStack {
                            Toggle(isOn: $autoCopyPreviousAnnotation) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("前の画像から自動コピー")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                    Text("新しい画像に移動時、前の画像のアノテーションをコピー")
                                        .font(.caption2)
                                        .foregroundColor(.gray.opacity(0.8))
                                }
                            }
                            .toggleStyle(SwitchToggleStyle(tint: .cyan))
                        }
                        .padding(.horizontal, 16)
                    }

                    Divider()
                        .background(Color.gray.opacity(0.5))
                        .padding(.horizontal, 16)

                    // Line annotation info section
                    VStack(spacing: 8) {
                        Text("Line Annotation")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tap a line in the right panel to select it")
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.8))

                            Text("Drag on the canvas to move the selected line")
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.8))

                            Text("Vertical lines: drag left/right")
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.8))

                            Text("Horizontal lines: drag up/down")
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.8))
                        }
                        .padding(.horizontal, 16)
                    }

                    // All Reset section
                    if onAllReset != nil {
                        Divider()
                            .background(Color.gray.opacity(0.5))
                            .padding(.horizontal, 16)

                        VStack(spacing: 12) {
                            Text("Danger Zone")
                                .font(.caption)
                                .foregroundColor(.red.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)

                            Button(action: {
                                showingAllResetConfirmation = true
                            }) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                    Text("All Reset")
                                }
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)

                            Text("画像・アノテーション・JSONをすべて削除します")
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.6))
                                .padding(.horizontal, 16)
                        }
                    }

                    Spacer()
                        .frame(height: 20)
                }
            }
            .frame(width: 220)
            .background(Color(white: 0.12))
        }
        .alert("All Reset", isPresented: $showingAllResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset All", role: .destructive) {
                isPresented = false
                onAllReset?()
            }
        } message: {
            Text("すべての画像、アノテーション、JSONファイルが削除されます。この操作は取り消せません。")
        }
    }

    private func resetImageSettings() {
        withAnimation(.easeOut(duration: 0.2)) {
            imageContrast = 1.0
            imageBrightness = 0.0
        }
    }
}

// MARK: - Settings Slider Component

/// Horizontal slider with label and value display
struct SettingsSliderView: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let displayFormatter: (Float) -> Int
    let displaySuffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title and value
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Text("\(displayFormatter(value))\(displaySuffix)")
                    .font(.caption)
                    .foregroundColor(.white)
                    .monospacedDigit()
            }

            // Slider track
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(white: 0.3))
                        .frame(height: 8)

                    // Filled portion
                    let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                    let centerPosition = range.contains(0) ? -range.lowerBound / (range.upperBound - range.lowerBound) : 0

                    if range.contains(0) {
                        // Bidirectional slider (like brightness: -1 to 1)
                        let fillStart = min(normalizedValue, centerPosition)
                        let fillWidth = abs(normalizedValue - centerPosition)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.cyan.opacity(0.6))
                            .frame(width: geometry.size.width * CGFloat(fillWidth), height: 8)
                            .offset(x: geometry.size.width * CGFloat(fillStart))
                    } else {
                        // Unidirectional slider (like contrast: 0 to 2)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.cyan.opacity(0.6))
                            .frame(width: geometry.size.width * CGFloat(normalizedValue), height: 8)
                    }

                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .shadow(radius: 2)
                        .offset(x: geometry.size.width * CGFloat(normalizedValue) - 10)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gestureValue in
                            let normalized = Float(gestureValue.location.x / geometry.size.width)
                            let clamped = min(max(normalized, 0), 1)
                            value = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
                        }
                )
            }
            .frame(height: 20)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(white: 0.15)
        ImageSettingsOverlayView(
            isPresented: .constant(true),
            imageContrast: .constant(1.0),
            imageBrightness: .constant(0.0),
            autoCopyPreviousAnnotation: .constant(false)
        )
    }
    .frame(width: 400, height: 600)
}
