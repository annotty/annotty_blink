#if os(macOS)
import SwiftUI

/// macOS menu bar commands for Annotty
struct AppMenuCommands: Commands {
    /// Shared view model reference for menu actions
    /// Note: This needs to be injected from the app
    @Binding var viewModel: CanvasViewModel?

    var body: some Commands {
        // File menu additions
        CommandGroup(after: .newItem) {
            Divider()

            Button("Import Image...") {
                // Open image panel (handled by NSOpenPanel)
                openImagePanel()
            }
            .keyboardShortcut("i", modifiers: .command)

            Button("Import Folder...") {
                openFolderPanel()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Divider()

            Button("Open Project...") {
                openProjectPanel()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
        }

        // Edit menu - Undo/Redo
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                viewModel?.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(viewModel == nil)

            Button("Redo") {
                viewModel?.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(viewModel == nil)
        }

        // Navigation menu
        CommandMenu("Navigate") {
            Button("Previous Image") {
                viewModel?.previousImage()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(viewModel == nil)

            Button("Next Image") {
                viewModel?.nextImage()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(viewModel == nil)

            Divider()

            Button("Fit to View") {
                viewModel?.resetView()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(viewModel == nil)
        }

        // Annotation menu
        CommandMenu("Annotation") {
            // Line selection shortcuts
            Section("Right Eye") {
                Button("Pupil Vertical") {
                    viewModel?.selectedLineType = .rightPupilVertical
                }
                .keyboardShortcut("1", modifiers: [])

                Button("Pupil Horizontal") {
                    viewModel?.selectedLineType = .rightPupilHorizontal
                }
                .keyboardShortcut("2", modifiers: [])

                Button("Upper Brow") {
                    viewModel?.selectedLineType = .rightUpperBrow
                }
                .keyboardShortcut("3", modifiers: [])

                Button("Lower Brow") {
                    viewModel?.selectedLineType = .rightLowerBrow
                }
                .keyboardShortcut("4", modifiers: [])

                Button("Upper Eyelid") {
                    viewModel?.selectedLineType = .rightUpperEyelid
                }
                .keyboardShortcut("5", modifiers: [])

                Button("Lower Eyelid") {
                    viewModel?.selectedLineType = .rightLowerEyelid
                }
                .keyboardShortcut("6", modifiers: [])
            }

            Divider()

            Section("Left Eye") {
                Button("Pupil Vertical") {
                    viewModel?.selectedLineType = .leftPupilVertical
                }
                .keyboardShortcut("q", modifiers: [])

                Button("Pupil Horizontal") {
                    viewModel?.selectedLineType = .leftPupilHorizontal
                }
                .keyboardShortcut("w", modifiers: [])

                Button("Upper Brow") {
                    viewModel?.selectedLineType = .leftUpperBrow
                }
                .keyboardShortcut("e", modifiers: [])

                Button("Lower Brow") {
                    viewModel?.selectedLineType = .leftLowerBrow
                }
                .keyboardShortcut("r", modifiers: [])

                Button("Upper Eyelid") {
                    viewModel?.selectedLineType = .leftUpperEyelid
                }
                .keyboardShortcut("t", modifiers: [])

                Button("Lower Eyelid") {
                    viewModel?.selectedLineType = .leftLowerEyelid
                }
                .keyboardShortcut("y", modifiers: [])
            }

            Divider()

            Button("Clear All Annotations") {
                viewModel?.clearAllAnnotations()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel == nil)
        }
    }

    // MARK: - File Panel Actions

    private func openImagePanel() {
        let panel = NSOpenPanel()
        panel.title = "Select Image"
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            viewModel?.importImage(from: url)
        }
    }

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Select Folder with Images"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            viewModel?.importImagesFromFolder(url)
        }
    }

    private func openProjectPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Project Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            viewModel?.openProject(at: url)
        }
    }
}
#endif
