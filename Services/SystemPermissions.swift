import Foundation
import AVFoundation
import CoreGraphics
import AppKit
import ScreenCaptureKit

/// Layanan untuk mengecek dan meminta izin akses sistem yang diperlukan untuk audio tap di macOS 14+.
public final class SystemPermissions: ObservableObject {
    public enum PermissionStatus: String, Sendable {
        case authorized = "Authorized"
        case denied = "Denied"
        case notDetermined = "Not Determined"
    }
    
    @Published public private(set) var audioCaptureStatus: PermissionStatus = .notDetermined
    @Published public private(set) var microphoneStatus: PermissionStatus = .notDetermined
    @Published public var isBannerDismissed: Bool = false
    
    public static let shared = SystemPermissions()
    
    public init() {
        refreshStatus()
        
        // Pemicu registrasi prompt izin sistem Screen & Audio Capture otomatis jika belum aktif
        if !CGPreflightScreenCaptureAccess() {
            requestAudioCapturePermission()
        }
        
        // Auto refresh saat pengguna kembali dari System Settings
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshStatus()
        }
    }
    
    /// Memperbarui status izin audio capture dan microphone saat ini
    public func refreshStatus() {
        // Cek izin Screen & Audio Capture (System Audio Recording di macOS Sonoma/Sequoia)
        if CGPreflightScreenCaptureAccess() {
            audioCaptureStatus = .authorized
            isBannerDismissed = true
        } else {
            audioCaptureStatus = .denied
            isBannerDismissed = false
        }
        
        // Cek izin Microphone (AVCaptureDevice)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneStatus = .authorized
        case .denied, .restricted:
            microphoneStatus = .denied
        case .notDetermined:
            microphoneStatus = .notDetermined
        @unknown default:
            microphoneStatus = .notDetermined
        }
    }
    
    /// Meminta izin audio capture (memicu prompt sistem macOS dan mendaftarkan aplikasi di Privacy & Security)
    public func requestAudioCapturePermission() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            Task {
                _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            }
        }
        refreshStatus()
    }
    
    /// Meminta izin audio capture dan langsung membuka halaman System Settings
    public func requestPermissions() {
        requestAudioCapturePermission()
        openSystemPrivacySettings()
    }
    
    /// Meminta izin akses microphone
    public func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.refreshStatus()
                completion(granted)
            }
        }
    }
    
    /// Membuka halaman Pengaturan Sistem (Privacy & Security) di macOS
    public func openSystemPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Me-restart aplikasi agar macOS menerapkan token izin TCC yang baru saja diaktifkan
    public func restartApp() {
        let appUrl = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", appUrl.path]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
}
