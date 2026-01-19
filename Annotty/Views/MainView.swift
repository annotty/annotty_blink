import SwiftUI

/// Main app view with the complete UI layout
/// Layout: Center canvas | Right panel
/// Top bar spans the full width
struct MainView: View {
    @StateObject private var viewModel = CanvasViewModel()
    @State private var showingExportSheet = false
    @State private var showingImagePicker = false
    @State private var showingImageSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            TopBarView(
                currentIndex: viewModel.currentImageIndex,
                totalCount: viewModel.totalImageCount,
                isLoading: viewModel.isLoading,
                isSaving: viewModel.isSaving,
                onPrevious: { viewModel.previousImage() },
                onNext: { viewModel.nextImage() },
                onGoTo: { index in viewModel.goToImage(index: index) },
                onResetView: { viewModel.resetView() },
                onClear: { viewModel.clearAllAnnotations() },
                onExport: { showingExportSheet = true },
                onLoad: { showingImagePicker = true },
                onReload: { viewModel.reloadImagesFromProject() },
                onDeleteImage: { viewModel.deleteCurrentImage() }
            )

            // Main content area
            HStack(spacing: 0) {
                // Center - Canvas (takes up remaining space)
                CanvasContainerView(viewModel: viewModel)

                // Right panel - Line selection
                RightPanelView(
                    viewModel: viewModel,
                    onSettingsTapped: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showingImageSettings = true
                        }
                    }
                )
                .frame(width: 130)
            }
        }
        .background(Color(white: 0.15))
        .ignoresSafeArea(.keyboard)
        .overlay {
            // Image settings slide-in panel
            if showingImageSettings {
                ImageSettingsOverlayView(
                    isPresented: $showingImageSettings,
                    imageContrast: $viewModel.imageContrast,
                    imageBrightness: $viewModel.imageBrightness
                )
                .transition(.move(edge: .trailing))
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePickerView(
                onImageSelected: { url in
                    viewModel.importImage(from: url)
                },
                onFolderSelected: { url in
                    viewModel.importImagesFromFolder(url)
                },
                onProjectSelected: { url in
                    viewModel.openProject(at: url)
                },
                onVideoSelected: { url in
                    // Video import will be handled in Phase 7
                    print("[Video] Selected: \(url.lastPathComponent)")
                }
            )
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportSheetView(viewModel: viewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // Save when app goes to background
            viewModel.saveBeforeBackground()
        }
    }
}

// MARK: - Preview

#Preview {
    MainView()
}
