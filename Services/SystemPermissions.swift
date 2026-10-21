import Foundation
import AVFoundation
import CoreGraphics
import AppKit

/// Layanan untuk mengecek dan meminta izin akses sistem yang diperlukan untuk audio tap di macOS 14+.
public final class SystemPermissions: ObservableObject {
    public enum PermissionStatus: String, Sendable {
        case authorized = "Authorized"
        case denied = "Denied"
        case notDetermined = "Not Determined"
    }
    
    @Published public private(set) var audioCaptureStatus: PermissionStatus = .notDetermined
    @Published public private(set) var microphoneStatus: PermissionStatus = .notDetermined
    
    public static let shared = SystemPermissions()
    
    public init() {
        refreshStatus()
    }
    
    /// Memperbarui status izin audio capture dan microphone saat ini
    public func refreshStatus() {
        // Cek izin Screen & Audio Capture (System Audio Recording di macOS Sonoma/Sequoia)
        if CGPreflightScreenCaptureAccess() {
            audioCaptureStatus = .authorized
        } else {
            audioCaptureStatus = .denied
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
    
    /// Meminta izin audio capture (akan memicu prompt sistem macOS jika belum pernah diminta)
    public func requestAudioCapturePermission() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        refreshStatus()
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
}
