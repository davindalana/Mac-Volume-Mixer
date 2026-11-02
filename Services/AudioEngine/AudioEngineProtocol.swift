import Foundation
import Combine
import CoreAudio

/// Kontrak protokol untuk Audio Driver / Audio Tap Engine.
/// Memfasilitasi abstraksi antara UI/ViewModel dengan implementasi CoreAudio konkret atau mock simulator.
public protocol AudioEngineProtocol: AnyObject, Sendable {
    /// Memulai monitoring proses audio sistem dan hardware stream
    func startMonitoring()
    
    /// Menghentikan monitoring dan melepaskan resource tap
    func stopMonitoring()
    
    /// Mengatur level volume untuk proses tertentu berdasarkan PID
    /// - Parameters:
    ///   - pid: Process ID aplikasi
    ///   - volume: Nilai volume dari 0.0 sampai 1.0
    func setVolume(for pid: pid_t, volume: Float)
    
    /// Mengatur level volume untuk aplikasi berdasarkan Bundle Identifier
    func setVolume(forBundleID bundleID: String, volume: Float)
    
    /// Mengatur status mute proses tertentu
    /// - Parameters:
    ///   - pid: Process ID aplikasi
    ///   - isMuted: true jika di-mute, false jika unmuted
    func setMute(for pid: pid_t, isMuted: Bool)
    
    /// Mengatur status mute aplikasi berdasarkan Bundle Identifier
    func setMute(forBundleID bundleID: String, isMuted: Bool)
    
    /// Mengatur output device khusus untuk proses tertentu berdasarkan PID
    func setOutputDevice(for pid: pid_t, deviceUID: String?)
    
    /// Mengatur output device khusus untuk aplikasi berdasarkan Bundle Identifier
    func setOutputDevice(forBundleID bundleID: String, deviceUID: String?)
    
    /// Mendapatkan volume master sistem saat ini (0.0 - 1.0)
    func getMasterVolume() -> Float
    
    /// Mengatur volume master sistem
    func setMasterVolume(_ volume: Float)
    
    /// Mengatur status mute master sistem
    func setMasterMute(_ isMuted: Bool)
    
    /// Mendapatkan status mute master sistem saat ini
    func getMasterMute() -> Bool
    
    /// Mengambil daftar perangkat output audio yang tersedia
    func getOutputDevices() -> [AudioDevice]
    
    /// Mengubah perangkat audio output default sistem
    func setDefaultOutputDevice(_ device: AudioDevice)
    
    // MARK: - Reactive Publishers / Streams
    
    /// Combine Publisher yang memancarkan daftar aplikasi yang sedang aktif menghasilkan/memproses audio
    var activeProcessesPublisher: AnyPublisher<[AudioProcess], Never> { get }
    
    /// Combine Publisher yang memancarkan daftar perangkat output audio
    var outputDevicesPublisher: AnyPublisher<[AudioDevice], Never> { get }
    
    /// Combine Publisher untuk perubahan volume master sistem
    var masterVolumePublisher: AnyPublisher<Float, Never> { get }
    
    /// Combine Publisher untuk perubahan status mute master sistem
    var masterMutePublisher: AnyPublisher<Bool, Never> { get }
}

public extension AudioEngineProtocol {
    func setVolume(forBundleID bundleID: String, volume: Float) {}
    func setMute(forBundleID bundleID: String, isMuted: Bool) {}
    func setOutputDevice(for pid: pid_t, deviceUID: String?) {}
    func setOutputDevice(forBundleID bundleID: String, deviceUID: String?) {}
}
