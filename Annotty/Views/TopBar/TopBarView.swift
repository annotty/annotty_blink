import SwiftUI

/// Top bar with image navigation and export button
struct TopBarView: View {
    let currentIndex: Int
    let totalCount: Int
    let isLoading: Bool
    let isSaving: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onGoTo: (Int) -> Void
    let onResetView: () -> Void
    let onExport: () -> Void
    let onLoad: () -> Void
    let onReload: () -> Void
    var onDeleteImage: (() -> Void)? = nil
    var onApplyPrevious: (() -> Void)? = nil
    var onUndo: (() -> Void)? = nil
    var onRedo: (() -> Void)? = nil

    @State private var showingHelp = false

    var body: some View {
        HStack {
            // Import button
            Button(action: onLoad) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                    Text("Import")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Undo/Redo buttons (Mac only - iPad uses 2/3 finger tap)
            if ProcessInfo.processInfo.isiOSAppOnMac {
                Button(action: { onUndo?() }) {
                    Image(systemName: "arrow.uturn.backward")
                        .padding(8)
                        .background(Color.gray.opacity(0.5))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(totalCount == 0)

                Button(action: { onRedo?() }) {
                    Image(systemName: "arrow.uturn.forward")
                        .padding(8)
                        .background(Color.gray.opacity(0.5))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(totalCount == 0)
            }

            // Reload button
            Button(action: onReload) {
                Image(systemName: "arrow.clockwise")
                    .padding(8)
                    .background(Color.gray.opacity(0.5))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Spacer()

            // Image navigation
            ImageNavigatorView(
                currentIndex: currentIndex,
                totalCount: totalCount,
                onPrevious: onPrevious,
                onNext: onNext,
                onGoTo: onGoTo,
                onDelete: onDeleteImage,
                onApplyPrevious: onApplyPrevious
            )

            // Loading/Saving indicator (fixed width to prevent layout shift)
            HStack(spacing: 6) {
                if isLoading || isSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                    Text(isLoading ? "Loading..." : "Saving...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 100, alignment: .leading)

            Spacer()

            // Help button
            Button { showingHelp = true } label: {
                Image(systemName: "questionmark.circle")
                    .font(.title3)
                    .padding(8)
                    .background(Color.gray.opacity(0.5))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingHelp) {
                HelpSheetView()
            }

            // Fit view button (reset pan/zoom/rotation)
            Button(action: onResetView) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                    Text("Fit")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.6))
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(totalCount == 0)

            // Export button
            Button(action: onExport) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(totalCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(white: 0.1))
    }
}

// MARK: - Help Sheet

/// Operation guide displayed from the help button
private struct HelpSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    helpSection("キーボード操作") {
                        helpRow("↑ ↓", "選択中ラインの位置を上下に微調整（1px単位）")
                        helpRow("A / Z", "ライン項目の切り替え（前 / 次）")
                        helpRow("← →", "前 / 次の画像に移動")
                        helpRow("⌘Z", "元に戻す（Undo）")
                        helpRow("⌘⇧Z", "やり直し（Redo）")
                    }

                    helpSection("タッチ / マウス操作") {
                        helpRow("ドラッグ", "選択中ラインを移動")
                        helpRow("2本指パン", "画像を移動")
                        helpRow("ピンチ", "ズーム")
                        helpRow("2本指回転", "画像を回転")
                    }

                    helpSection("タッチジェスチャー（iPad）") {
                        helpRow("2本指タップ", "元に戻す（Undo）")
                        helpRow("3本指タップ", "やり直し（Redo）")
                    }

                    helpSection("ボタン") {
                        helpRow("Import", "画像・フォルダ・動画・JSONの読み込み")
                        helpRow("Fit", "表示をリセット（パン/ズーム/回転）")
                        helpRow("Export", "アノテーションデータの書き出し")
                    }
                }
                .padding(24)
            }
            .background(Color(white: 0.15))
            .navigationTitle("操作ガイド")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func helpSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            content()
        }
    }

    private func helpRow(_ key: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(key)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.cyan)
                .frame(width: 100, alignment: .leading)
            Text(description)
                .foregroundColor(.gray)
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    TopBarView(
        currentIndex: 12,
        totalCount: 128,
        isLoading: false,
        isSaving: false,
        onPrevious: {},
        onNext: {},
        onGoTo: { _ in },
        onResetView: {},
        onExport: {},
        onLoad: {},
        onReload: {},
        onDeleteImage: {},
        onApplyPrevious: {}
    )
}
