import Foundation
import SwiftUI
import Combine
import AppKit

/// ViewModel utama untuk mengelola state volume mixer, debouncing input slider,
/// daftar pinned apps (seperti SoundSource), dan integrasi dengan CoreAudio.
@MainActor
public final class MixerViewModel: ObservableObject {
    // MARK: - Published Properties
    
    /// Daftar seluruh proses audio yang terdeteksi secara aktual oleh audio engine
    @Published public private(set) var processes: [AudioProcess] = []
    
    /// Daftar Bundle ID aplikasi yang di-pin di mixer (SoundSource style)
    @Published public var pinnedAppBundleIDs: [String] {
        didSet {
            UserDefaults.standard.set(pinnedAppBundleIDs, forKey: "pinnedAppBundleIDs")
        }
    }
    
    /// Volume tersimpan per bundle ID
    private var savedAppVolumes: [String: Float] {
        get { (UserDefaults.standard.dictionary(forKey: "savedAppVolumes") as? [String: Float]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "savedAppVolumes") }
    }
    
    /// Mute tersimpan per bundle ID
    private var savedAppMutes: [String: Bool] {
        get { (UserDefaults.standard.dictionary(forKey: "savedAppMutes") as? [String: Bool]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "savedAppMutes") }
    }
    
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
    
    /// Flag apakah banner izin telah di-dismiss oleh pengguna (tersimpan di UserDefaults)
    @Published public var isBannerDismissed: Bool {
        didSet {
            systemPermissions.isBannerDismissed = isBannerDismissed
            UserDefaults.standard.set(isBannerDismissed, forKey: "hasDismissedAudioPermissionBanner")
        }
    }
    
    // MARK: - Displayed Processes (SoundSource UI Model)
    
    /// Daftar proses yang ditampilkan di mixer antarmuka pengguna
    public var displayProcesses: [AudioProcess] {
        var result: [AudioProcess] = []
        var includedBundleIDs = Set<String>()
        var includedPIDs = Set<pid_t>()
        
        // 1. Tampilkan semua aplikasi yang di-pin
        for bundleID in pinnedAppBundleIDs {
            let lowerBID = bundleID.lowercased()
            includedBundleIDs.insert(lowerBID)
            
            // Cari proses yang sedang berjalan dengan bundleID tersebut
            if let activeProc = processes.first(where: {
                ($0.bundleIdentifier?.lowercased() == lowerBID) ||
                ($0.appName.lowercased() == appNameFromBundleID(bundleID).lowercased())
            }) {
                result.append(activeProc)
                includedPIDs.insert(activeProc.pid)
            } else if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                // Aplikasi sedang berjalan di sistem, gunakan PID sebenarnya jika valid
                let pid = runningApp.processIdentifier > 0 ? runningApp.processIdentifier : pid_t(bundleID.hashValue & 0x7FFFFFFF)
                let savedVol = savedAppVolumes[bundleID] ?? 1.0
                let savedMute = savedAppMutes[bundleID] ?? false
                let proc = AudioProcess(
                    pid: pid,
                    appName: runningApp.localizedName ?? appNameFromBundleID(bundleID),
                    bundleIdentifier: bundleID,
                    icon: runningApp.icon ?? appMetadata(for: bundleID).icon,
                    volume: savedVol,
                    isMuted: savedMute,
                    isPlayingAudio: false
                )
                result.append(proc)
                includedPIDs.insert(pid)
            } else {
                // Aplikasi sedang tidak berjalan, buat placeholder dengan metadata aplikasi
                let info = appMetadata(for: bundleID)
                let savedVol = savedAppVolumes[bundleID] ?? 1.0
                let savedMute = savedAppMutes[bundleID] ?? false
                let placeholder = AudioProcess(
                    pid: pid_t(bundleID.hashValue & 0x7FFFFFFF),
                    appName: info.name,
                    bundleIdentifier: bundleID,
                    icon: info.icon,
                    volume: savedVol,
                    isMuted: savedMute,
                    isPlayingAudio: false
                )
                result.append(placeholder)
            }
        }
        
        // 2. Tambahkan otomatis aplikasi lain yang sedang memutar audio atau yang ada di list proses
        for proc in processes {
            let bID = (proc.bundleIdentifier ?? "").lowercased()
            if !includedBundleIDs.contains(bID) && !includedPIDs.contains(proc.pid) {
                if proc.isPlayingAudio || abs(proc.volume - 1.0) > 0.001 || proc.isMuted {
                    result.append(proc)
                    includedPIDs.insert(proc.pid)
                    if !bID.isEmpty { includedBundleIDs.insert(bID) }
                }
            }
        }
        
        // Filter jika user mengetik pencarian
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return result.filter {
                $0.appName.localizedCaseInsensitiveContains(searchQuery) ||
                ($0.bundleIdentifier?.localizedCaseInsensitiveContains(searchQuery) ?? false)
            }
        }
        
        return result
    }
    
    /// Aplikasi berjalan yang dapat ditambahkan ke mixer
    public var availableRunningApps: [NSRunningApplication] {
        let currentPinned = Set(pinnedAppBundleIDs.map { $0.lowercased() })
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { app in
                guard let bID = app.bundleIdentifier?.lowercased() else { return false }
                return !currentPinned.contains(bID)
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
    
    // MARK: - Private Subjects & Dependencies
    private let audioEngine: AudioEngineProtocol
    private let systemPermissions: SystemPermissions
    private var cancellables = Set<AnyCancellable>()
    
    private let volumeUpdateSubject = PassthroughSubject<(pid: pid_t, volume: Float), Never>()
    private let masterVolumeUpdateSubject = PassthroughSubject<Float, Never>()
    
    // MARK: - Initializer
    public init(
        audioEngine: AudioEngineProtocol = CoreAudioTapService(),
        systemPermissions: SystemPermissions = .shared
    ) {
        self.audioEngine = audioEngine
        self.systemPermissions = systemPermissions
        
        // Muat pinned apps tersimpan, default ke aplikasi utama seperti pada screenshot
        let savedPinned = UserDefaults.standard.stringArray(forKey: "pinnedAppBundleIDs")
        self.pinnedAppBundleIDs = savedPinned ?? [
            "com.apple.finder",
            "com.apple.Music",
            "com.apple.Safari",
            "net.whatsapp.WhatsApp"
        ]
        
        self.isBannerDismissed = UserDefaults.standard.bool(forKey: "hasDismissedAudioPermissionBanner")
        
        setupSubscriptions()
        setupDebouncedSliders()
        startMonitoring()
    }
    
    // MARK: - Subscriptions & Debounce Setup
    
    private func setupSubscriptions() {
        audioEngine.activeProcessesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedProcesses in
                self?.processes = updatedProcesses
            }
            .store(in: &cancellables)
        
        audioEngine.outputDevicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.outputDevices = devices
                self?.selectedOutputDevice = devices.first(where: { $0.isDefault }) ?? devices.first
            }
            .store(in: &cancellables)
        
        audioEngine.masterVolumePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] vol in
                guard let self = self else { return }
                if self.masterVolume <= 1.0 || vol < 1.0 {
                    self.masterVolume = vol
                }
            }
            .store(in: &cancellables)
        
        audioEngine.masterMutePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in
                self?.isMasterMuted = muted
            }
            .store(in: &cancellables)
        
        systemPermissions.$audioCaptureStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.permissionStatus = status
            }
            .store(in: &cancellables)
    }
    
    private func setupDebouncedSliders() {
        volumeUpdateSubject
            .debounce(for: .milliseconds(40), scheduler: DispatchQueue.global(qos: .userInteractive))
            .sink { [weak self] update in
                self?.audioEngine.setVolume(for: update.pid, volume: update.volume)
            }
            .store(in: &cancellables)
        
        masterVolumeUpdateSubject
            .debounce(for: .milliseconds(40), scheduler: DispatchQueue.global(qos: .userInteractive))
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
    
    public func updateVolume(for pid: pid_t, volume: Float) {
        let clamped = max(0.0, min(2.0, volume))
        
        var targetBundleID: String? = nil
        var targetPID: pid_t = pid
        
        if let index = processes.firstIndex(where: { $0.pid == pid }) {
            processes[index].volume = clamped
            targetBundleID = processes[index].bundleIdentifier
            if clamped > 0 && processes[index].isMuted {
                processes[index].isMuted = false
                audioEngine.setMute(for: pid, isMuted: false)
            }
        }
        
        // Cek juga di displayProcesses untuk placeholder / pinned apps
        if let disp = displayProcesses.first(where: { $0.pid == pid }) {
            targetBundleID = targetBundleID ?? disp.bundleIdentifier
        }
        
        // Simpan preferensi volume dan sinkronkan ke audio engine
        if let bundleID = targetBundleID {
            var dict = savedAppVolumes
            dict[bundleID] = clamped
            savedAppVolumes = dict
            
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first, running.processIdentifier > 0 {
                targetPID = running.processIdentifier
            }
            
            audioEngine.setVolume(forBundleID: bundleID, volume: clamped)
        }
        
        if targetPID > 0 {
            audioEngine.setVolume(for: targetPID, volume: clamped)
            volumeUpdateSubject.send((pid: targetPID, volume: clamped))
        }
        objectWillChange.send()
    }
    
    public func toggleMute(for pid: pid_t) {
        var targetBundleID: String? = nil
        var targetPID: pid_t = pid
        var newMuted: Bool = true
        
        if let index = processes.firstIndex(where: { $0.pid == pid }) {
            newMuted = !processes[index].isMuted
            processes[index].isMuted = newMuted
            targetBundleID = processes[index].bundleIdentifier
        } else if let disp = displayProcesses.first(where: { $0.pid == pid }) {
            newMuted = !disp.isMuted
            targetBundleID = disp.bundleIdentifier
        }
        
        if let bundleID = targetBundleID {
            var dict = savedAppMutes
            dict[bundleID] = newMuted
            savedAppMutes = dict
            
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first, running.processIdentifier > 0 {
                targetPID = running.processIdentifier
            }
            
            audioEngine.setMute(forBundleID: bundleID, isMuted: newMuted)
        }
        
        if targetPID > 0 {
            audioEngine.setMute(for: targetPID, isMuted: newMuted)
        }
        objectWillChange.send()
    }
    
    public func updateMasterVolume(_ volume: Float) {
        let clamped = max(0.0, min(2.0, volume))
        self.masterVolume = clamped
        if clamped > 0 && isMasterMuted {
            isMasterMuted = false
            audioEngine.setMasterMute(false)
        }
        audioEngine.setMasterVolume(min(1.0, clamped))
        masterVolumeUpdateSubject.send(clamped)
    }
    
    public func toggleMasterMute() {
        let newMuted = !isMasterMuted
        isMasterMuted = newMuted
        audioEngine.setMasterMute(newMuted)
    }
    
    public func selectOutputDevice(_ device: AudioDevice) {
        selectedOutputDevice = device
        audioEngine.setDefaultOutputDevice(device)
    }
    
    public func addPinnedApp(bundleIdentifier: String) {
        guard !pinnedAppBundleIDs.contains(where: { $0.lowercased() == bundleIdentifier.lowercased() }) else { return }
        pinnedAppBundleIDs.append(bundleIdentifier)
        refresh()
    }
    
    public func removePinnedApp(bundleIdentifier: String) {
        pinnedAppBundleIDs.removeAll { $0.lowercased() == bundleIdentifier.lowercased() }
        refresh()
    }
    
    public func chooseAppFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Pilih aplikasi untuk ditambahkan ke Mac Volume Mixer"
        
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                addPinnedApp(bundleIdentifier: bundleID)
            }
        }
    }
    
    public func refresh() {
        if let tapService = audioEngine as? CoreAudioTapService {
            tapService.refreshAudioProcesses()
        }
        systemPermissions.refreshStatus()
    }
    
    public func requestPermissions() {
        systemPermissions.openSystemPrivacySettings()
    }
    
    public func dismissPermissionBanner() {
        isBannerDismissed = true
        systemPermissions.isBannerDismissed = true
    }
    
    public func restartApp() {
        systemPermissions.restartApp()
    }
    
    public func showSafariGuide() {
        let alert = NSAlert()
        alert.messageText = "Kontrol Volume YouTube di Safari"
        alert.informativeText = """
        Untuk mengatur volume tab/video YouTube di Safari secara fleksibel (0% - 100%):

        1. Buka Safari > Settings (Cmd + ,) > Advanced.
        2. Centang "Show features for web developers".
        3. Di Menu Bar Safari atas, klik menu "Develop" > centang "Allow JavaScript from Apple Events".

        Selesai! Slider volume Mac Volume Mixer akan langsung mengatur volume YouTube secara real-time.

        (Catatan: Fungsi Mute hardware selalu aktif otomatis tanpa perlu pengaturan ini)
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Mengerti")
        alert.runModal()
    }
    
    public func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Metadata Helpers
    
    private func appMetadata(for bundleID: String) -> (name: String, icon: NSImage?) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return (cleanName(name), icon)
        }
        
        let fallbackName = appNameFromBundleID(bundleID)
        let appIcon: NSImage
        if #available(macOS 12.0, *) {
            appIcon = NSWorkspace.shared.icon(for: .application)
        } else {
            appIcon = NSWorkspace.shared.icon(forFileType: "app")
        }
        return (fallbackName, appIcon)
    }
    
    private func appNameFromBundleID(_ bundleID: String) -> String {
        switch bundleID.lowercased() {
        case "com.apple.finder": return "Finder"
        case "com.apple.music": return "Music"
        case "com.apple.safari": return "Safari"
        case "net.whatsapp.whatsapp": return "WhatsApp"
        case "com.google.chrome": return "Google Chrome"
        case "com.spotify.client": return "Spotify"
        default:
            let comps = bundleID.components(separatedBy: ".")
            return comps.last?.capitalized ?? bundleID
        }
    }
    
    private func cleanName(_ name: String) -> String {
        return name
            .replacingOccurrences(of: "\u{200E}", with: "")
            .replacingOccurrences(of: ".app", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
