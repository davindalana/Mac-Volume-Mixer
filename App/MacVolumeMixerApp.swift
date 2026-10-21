import SwiftUI

/// Entry point utama aplikasi macOS Volume Mixer.
/// Menjalankan aplikasi secara native di Menu Bar menggunakan SwiftUI `MenuBarExtra` dengan gaya `.window`.
@main
struct MacVolumeMixerApp: App {
    @StateObject private var viewModel = MixerViewModel()
    
    var body: some Scene {
        MenuBarExtra {
            PopoverView(viewModel: viewModel)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "slider.vertical.3")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
