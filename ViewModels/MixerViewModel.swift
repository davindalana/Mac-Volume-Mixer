import Foundation
import SwiftUI
import Combine

/// ViewModel utama untuk mengelola state volume mixer, debouncing input slider,
/// dan integrasi antara `AudioEngineProtocol`, `ProcessWatcher`, dan `SystemPermissions`.
@MainActor
public final class MixerViewModel: ObservableObject {
    // MARK: - Published Properties
    
    /// Daftar seluruh proses audio yang terdeteksi
    @Published public private(set) var processes: [AudioProcess] = []
    
    /// Query pencarian aplikasi
    @Published public var searchQuery: String = ""
    
    /// Daftar perangkat output audio yang terpasang
    @Published public private(set) var outputDevices: [AudioDevice] = []
    
    /// Perangkat output yang sedang aktif/dipilih
    @Published public private(set) var selectedOutputDevice: AudioDevice?
    
    /// Level volume master sistem (0.0 ... 1.0)
    @Published public var masterVolume: Float = 1.0
    
    /// Status mute master sistem
    @Published public var isMasterMuted: Bool = false
    
    /// Status apakah engine sedang aktif memonitor
    @Published public private(set) var isMonitoring: Bool = false
    
    /// Status izin sistem
    @Published public private(set) var permissionStatus: SystemPermissions.PermissionStatus = .authorized
    
    // MARK: - Filtered Processes
    
    /// Daftar proses audio yang difilter berdasarkan searchQuery
    public var filteredProcesses: [AudioProcess] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return processes
        }
        return processes.filter {
            $0.appName.localizedCaseInsensitiveContains(searchQuery) ||
            ($0.bundleIdentifier?.localizedCaseInsensitiveContains(searchQuery) ?? false)
        }
    }
    
    // MARK: - Private Subjects & Dependencies
    private let audioEngine: AudioEngineProtocol
    private let systemPermissions: SystemPermissions
    private var cancellables = Set<AnyCancellable>()
    
    /// Subject untuk debounce update volume slider per PID (50ms)
    private let volumeUpdateSubject = PassthroughSubject<(pid: pid_t, volume: Float), Never>()
    
    /// Subject untuk debounce update volume master (50ms)
    private let masterVolumeUpdateSubject = PassthroughSubject<Float, Never>()
    
    // MARK: - Initializer
    public init(
        audioEngine: AudioEngineProtocol = CoreAudioTapService(),
        systemPermissions: SystemPermissions = .shared
    ) {
        self.audioEngine = audioEngine
        self.systemPermissions = systemPermissions
        
        setupSubscriptions()
        setupDebouncedSliders()
        startMonitoring()
    }
    
    // MARK: - Subscriptions & Debounce Setup
    
    private func setupSubscriptions() {
        // Berlangganan perubahan proses aktif dari audio engine
        audioEngine.activeProcessesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedProcesses in
                self?.processes = updatedProcesses
            }
            .store(in: &cancellables)
        
        // Berlangganan perubahan output devices
        audioEngine.outputDevicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.outputDevices = devices
                self?.selectedOutputDevice = devices.first(where: { $0.isDefault }) ?? devices.first
            }
            .store(in: &cancellables)
        
        // Berlangganan perubahan master volume hardware
        audioEngine.masterVolumePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] vol in
                self?.masterVolume = vol
            }
            .store(in: &cancellables)
        
        // Berlangganan status master mute
        audioEngine.masterMutePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in
                self?.isMasterMuted = muted
            }
            .store(in: &cancellables)
        
        // Observasi izin sistem
        systemPermissions.$audioCaptureStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.permissionStatus = status
            }
            .store(in: &cancellables)
    }
    
    /// Mengatur debounce (50ms) pada slider volume agar tidak membanjiri C-API CoreAudio
    private func setupDebouncedSliders() {
        // Debounce volume aplikasi
        volumeUpdateSubject
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.global(qos: .userInteractive))
            .sink { [weak self] update in
                self?.audioEngine.setVolume(for: update.pid, volume: update.volume)
            }
            .store(in: &cancellables)
        
        // Debounce master volume
        masterVolumeUpdateSubject
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.global(qos: .userInteractive))
            .sink { [weak self] volume in
                self?.audioEngine.setMasterVolume(volume)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Actions
    
    public func startMonitoring() {
        audioEngine.startMonitoring()
        isMonitoring = true
        masterVolume = audioEngine.getMasterVolume()
        isMasterMuted = audioEngine.getMasterMute()
    }
    
    public func stopMonitoring() {
        audioEngine.stopMonitoring()
        isMonitoring = false
    }
    
    /// Dipanggil saat slider volume aplikasi digeser oleh pengguna.
    /// Memperbarui state lokal seketika (optimistic UI update) dan mengirim ke pipeline debounce.
    public func updateVolume(for pid: pid_t, volume: Float) {
        let clamped = max(0.0, min(1.0, volume))
        if let index = processes.firstIndex(where: { $0.pid == pid }) {
            processes[index].volume = clamped
            // Jika sebelumnya muted dan slider digeser naik, buka mute otomatis
            if clamped > 0 && processes[index].isMuted {
                processes[index].isMuted = false
                audioEngine.setMute(for: pid, isMuted: false)
            }
        }
        volumeUpdateSubject.send((pid: pid, volume: clamped))
    }
    
    /// Toggle mute untuk aplikasi individual
    public func toggleMute(for pid: pid_t) {
        if let index = processes.firstIndex(where: { $0.pid == pid }) {
            let newMuted = !processes[index].isMuted
            processes[index].isMuted = newMuted
            audioEngine.setMute(for: pid, isMuted: newMuted)
        }
    }
    
    /// Update master volume
    public func updateMasterVolume(_ volume: Float) {
        let clamped = max(0.0, min(1.0, volume))
        self.masterVolume = clamped
        if clamped > 0 && isMasterMuted {
            isMasterMuted = false
            audioEngine.setMasterMute(false)
        }
        masterVolumeUpdateSubject.send(clamped)
    }
    
    /// Toggle mute untuk volume master sistem
    public func toggleMasterMute() {
        let newMuted = !isMasterMuted
        isMasterMuted = newMuted
        audioEngine.setMasterMute(newMuted)
    }
    
    /// Memilih perangkat audio output yang dituju
    public func selectOutputDevice(_ device: AudioDevice) {
        selectedOutputDevice = device
        audioEngine.setDefaultOutputDevice(device)
    }
    
    /// Menyegarkan daftar proses audio secara manual
    public func refresh() {
        if let tapService = audioEngine as? CoreAudioTapService {
            tapService.refreshAudioProcesses()
        }
        systemPermissions.refreshStatus()
    }
    
    /// Membuka izin preferensi sistem macOS
    public func requestPermissions() {
        systemPermissions.openSystemPrivacySettings()
    }
    
    /// Menutup aplikasi macOS
    public func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
