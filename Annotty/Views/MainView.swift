import SwiftUI

/// Main app view with the complete UI layout
/// Layout: Center canvas | Right panel
/// Top bar spans the full width
struct MainView: View {
    @StateObject private var viewModel = CanvasViewModel()
    @State private var showingExportSheet = false
    @State private var showingImagePicker = false
    @State private var showingImageSettings = false

    #if os(macOS)
    /// Binding to share view model with menu commands
    var viewModelBinding: Binding<CanvasViewModel?>?

    init(viewModelBinding: Binding<CanvasViewModel?>? = nil) {
        self.viewModelBinding = viewModelBinding
    }
    #endif

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
                onExport: { showingExportSheet = true },
                onLoad: { showingImagePicker = true },
                onReload: { viewModel.reloadImagesFromProject() },
                onDeleteImage: { viewModel.deleteCurrentImage() },
                onApplyPrevious: { viewModel.inheritFromPreviousFrame() },
                onUndo: { viewModel.undo() },
                onRedo: { viewModel.redo() },
                onClearAnnotation: { viewModel.clearAllAnnotations() }
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
                    },
                    onAutoDetect: { viewModel.autoDetectEyes() },
                    isDetecting: viewModel.isDetectingEyes
                )
                .frame(width: 130)
            }
        }
        .background(Color(white: 0.15))
        #if os(iOS)
        .ignoresSafeArea(.keyboard)
        #endif
        .overlay {
            // Image settings slide-in panel
            if showingImageSettings {
                ImageSettingsOverlayView(
                    isPresented: $showingImageSettings,
                    imageContrast: $viewModel.imageContrast,
                    imageBrightness: $viewModel.imageBrightness,
                    autoCopyPreviousAnnotation: $viewModel.autoCopyPreviousAnnotation,
                    onAllReset: { viewModel.resetAll() }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePickerView(
                onImageSelected: { url in
                    viewModel.importImage(from: url)
                },
                onImagesSelected: { urls in
                    viewModel.importImages(from: urls)
                },
                onFolderSelected: { url in
                    viewModel.importImagesFromFolder(url)
                },
                onAnnotationFileSelected: { url in
                    viewModel.importAnnotationFile(from: url)
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
        .alert("Import Result", isPresented: $viewModel.showImportResultAlert) {
            Button("OK", role: .cancel) {
                viewModel.importResultMessage = nil
            }
        } message: {
            Text(viewModel.importResultMessage ?? "")
        }
        .alert("Eye Detection Error", isPresented: $viewModel.showEyeDetectionError) {
            Button("OK", role: .cancel) {
                viewModel.eyeDetectionError = nil
            }
        } message: {
            Text(viewModel.eyeDetectionError ?? "")
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // Save when app goes to background (iOS)
            viewModel.saveBeforeBackground()
        }
        #elseif os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            // Save when app goes to background (macOS)
            viewModel.saveBeforeBackground()
        }
        .onAppear {
            // Share view model with menu commands on macOS
            viewModelBinding?.wrappedValue = viewModel
        }
        .onDisappear {
            viewModelBinding?.wrappedValue = nil
        }
        #endif
    }
}

// MARK: - Preview

#Preview {
    #if os(iOS)
    MainView()
    #elseif os(macOS)
    MainView(viewModelBinding: nil)
    #endif
}

// MARK: - Private Helpers

extension MainView {
}
