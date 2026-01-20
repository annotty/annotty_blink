import SwiftUI

@main
struct AnnottyApp: App {
    #if os(macOS)
    /// Shared view model for menu command access
    @State private var viewModel: CanvasViewModel? = nil
    #endif

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
            MainView()
            #elseif os(macOS)
            MainView(viewModelBinding: $viewModel)
                .frame(minWidth: 900, minHeight: 600)
            #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .commands {
            AppMenuCommands(viewModel: $viewModel)
        }
        #endif
    }
}
