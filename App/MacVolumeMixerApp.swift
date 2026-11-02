import SwiftUI
import AppKit

/// Delegate untuk memastikan hanya ada satu instance MacVolumeMixer yang berjalan
/// dan memicu permintaan izin yang diperlukan sejak awal.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "com.macvolumemixer.app"
        let runningInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in runningInstances {
            if app.processIdentifier != currentPID {
                // Instance lain sudah berjalan, tutup instance duplikat ini
                NSApplication.shared.terminate(nil)
                return
            }
        }
        
        // Pemicu registrasi prompt izin sistem Screen & Audio Capture
        SystemPermissions.shared.requestAudioCapturePermission()
    }
}

/// Entry point utama aplikasi macOS Volume Mixer.
/// Menjalankan aplikasi secara native di Menu Bar menggunakan SwiftUI `MenuBarExtra` dengan gaya `.window`.
@main
struct MacVolumeMixerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = MixerViewModel()
    
    var body: some Scene {
        MenuBarExtra {
            PopoverView(viewModel: viewModel)
        } label: {
            Image(systemName: "slider.vertical.3")
        }
        .menuBarExtraStyle(.window)
    }
}
