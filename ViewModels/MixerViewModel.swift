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
    
    /// Volume dan Mute tersimpan per bundle ID (in-memory cache dengan debounced disk write)
    private var inMemorySavedAppVolumes: [String: Float] = [:]
    private var inMemorySavedAppMutes: [String: Bool] = [:]
    private var inMemorySavedAppOutputDevices: [String: String] = [:]
    private let preferencesSaveSubject = PassthroughSubject<Void, Never>()
    
    public var savedAppVolumes: [String: Float] {
        get { inMemorySavedAppVolumes }
        set {
            inMemorySavedAppVolumes = newValue
            preferencesSaveSubject.send()
        }
    }
    
    public var savedAppMutes: [String: Bool] {
        get { inMemorySavedAppMutes }
        set {
            inMemorySavedAppMutes = newValue
            preferencesSaveSubject.send()
        }
    }
    
    public var savedAppOutputDevices: [String: String] {
        get { inMemorySavedAppOutputDevices }
        set {
            inMemorySavedAppOutputDevices = newValue
            preferencesSaveSubject.send()
        }
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
        
        // 1. Tampilkan semua aplikasi yang di-pin (HANYA jika aplikasi tersebut sedang berjalan / running)
        for bundleID in pinnedAppBundleIDs {
            let lowerBID = bundleID.lowercased()
            
            // Cari proses yang sedang berjalan dengan bundleID tersebut
            if let activeProc = processes.first(where: {
                ($0.bundleIdentifier?.lowercased() == lowerBID) ||
                ($0.appName.lowercased() == appNameFromBundleID(bundleID).lowercased())
            }) {
                var proc = activeProc
                if let savedDev = inMemorySavedAppOutputDevices[bundleID] {
                    proc.outputDeviceUID = savedDev
                }
                result.append(proc)
                includedBundleIDs.insert(lowerBID)
                includedPIDs.insert(activeProc.pid)
            } else if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                let realProc = processes.first(where: { $0.bundleIdentifier?.lowercased() == lowerBID })
                let pid = runningApp.processIdentifier > 0 ? runningApp.processIdentifier : (realProc?.pid ?? pid_t(bundleID.hashValue & 0x7FFFFFFF))
                let savedVol = inMemorySavedAppVolumes[bundleID] ?? 1.0
                let savedMute = inMemorySavedAppMutes[bundleID] ?? false
                let savedDev = inMemorySavedAppOutputDevices[bundleID]
                let proc = AudioProcess(
                    pid: pid,
                    appName: runningApp.localizedName ?? appNameFromBundleID(bundleID),
                    bundleIdentifier: bundleID,
                    icon: runningApp.icon ?? appMetadata(for: bundleID).icon,
                    volume: savedVol,
                    isMuted: savedMute,
                    isPlayingAudio: realProc?.isPlayingAudio ?? false,
                    outputDeviceUID: savedDev
                )
                result.append(proc)
                includedBundleIDs.insert(lowerBID)
                includedPIDs.insert(pid)
            }
            // Catatan: Jika aplikasi yang di-pin sedang tidak berjalan, tidak dimasukkan agar mixer bersih dan optimal!
        }
        
        // 2. Tambahkan otomatis aplikasi lain yang sedang memutar audio atau yang ada di list proses
        for proc in processes {
            guard let bID = proc.bundleIdentifier, !bID.isEmpty else { continue }
            let lowerBID = bID.lowercased()
            let name = proc.appName.lowercased()
            
            // Strict filtering: Jangan pernah tampilkan ghost "Process [pid]", helper, daemon, atau system process
            if name.hasPrefix("process") || name.contains("helper") || name.isEmpty || proc.icon == nil {
                continue
            }
            if lowerBID.contains("corespeech") || lowerBID.contains("mediaremote") || lowerBID.contains("audiomxd") ||
               lowerBID.contains("controlcenter") || lowerBID.contains("universalaccessd") || lowerBID.contains("powerchime") ||
               lowerBID.contains("webkit") || lowerBID.contains("helper") || lowerBID.contains("xpc") ||
               lowerBID.contains("systemstat") || lowerBID.contains("perfpower") {
                continue
            }
            
            if !includedBundleIDs.contains(lowerBID) && !includedPIDs.contains(proc.pid) {
                if proc.isPlayingAudio || abs(proc.volume - 1.0) > 0.001 || proc.isMuted {
                    result.append(proc)
                    includedPIDs.insert(proc.pid)
                    includedBundleIDs.insert(lowerBID)
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
        
        self.inMemorySavedAppVolumes = (UserDefaults.standard.dictionary(forKey: "savedAppVolumes") as? [String: Float]) ?? [:]
        self.inMemorySavedAppMutes = (UserDefaults.standard.dictionary(forKey: "savedAppMutes") as? [String: Bool]) ?? [:]
        self.inMemorySavedAppOutputDevices = (UserDefaults.standard.dictionary(forKey: "savedAppOutputDevices") as? [String: String]) ?? [:]
        self.isBannerDismissed = UserDefaults.standard.bool(forKey: "hasDismissedAudioPermissionBanner")
        
        setupSubscriptions()
        startMonitoring()
    }
    
    // MARK: - Subscriptions & Debounce Setup
    
    private func setupSubscriptions() {
        // Debounce penyimpanan preferensi ke UserDefaults agar disk I/O tidak memicu delay saat slider digeser
        preferencesSaveSubject
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.global(qos: .utility))
            .sink { [weak self] in
                guard let self = self else { return }
                UserDefaults.standard.set(self.inMemorySavedAppVolumes, forKey: "savedAppVolumes")
                UserDefaults.standard.set(self.inMemorySavedAppMutes, forKey: "savedAppMutes")
                UserDefaults.standard.set(self.inMemorySavedAppOutputDevices, forKey: "savedAppOutputDevices")
            }
            .store(in: &cancellables)
        
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
    
    public func updateVolume(for process: AudioProcess, volume: Float) {
        let clamped = max(0.0, min(2.0, volume))
        let targetBundleID = process.bundleIdentifier
        let pid = process.pid
        
        if let index = processes.firstIndex(where: { $0.pid == pid || ($0.bundleIdentifier != nil && $0.bundleIdentifier == targetBundleID) }) {
            processes[index].volume = clamped
            if clamped > 0 && processes[index].isMuted {
                processes[index].isMuted = false
                audioEngine.setMute(for: pid, isMuted: false)
            }
        }
        
        if let bundleID = targetBundleID {
            inMemorySavedAppVolumes[bundleID] = clamped
            preferencesSaveSubject.send()
            audioEngine.setVolume(forBundleID: bundleID, volume: clamped)
        }
        
        if pid > 0 {
            audioEngine.setVolume(for: pid, volume: clamped)
        }
    }
    
    public func updateVolume(for pid: pid_t, volume: Float) {
        if let proc = displayProcesses.first(where: { $0.pid == pid }) {
            updateVolume(for: proc, volume: volume)
        } else {
            let clamped = max(0.0, min(2.0, volume))
            audioEngine.setVolume(for: pid, volume: clamped)
        }
    }
    
    public func toggleMute(for process: AudioProcess) {
        let targetBundleID = process.bundleIdentifier
        let pid = process.pid
        var newMuted = !process.isMuted
        
        if let index = processes.firstIndex(where: { $0.pid == pid || ($0.bundleIdentifier != nil && $0.bundleIdentifier == targetBundleID) }) {
            newMuted = !processes[index].isMuted
            processes[index].isMuted = newMuted
        }
        
        if let bundleID = targetBundleID {
            inMemorySavedAppMutes[bundleID] = newMuted
            preferencesSaveSubject.send()
            audioEngine.setMute(forBundleID: bundleID, isMuted: newMuted)
        }
        
        if pid > 0 {
            audioEngine.setMute(for: pid, isMuted: newMuted)
        }
        objectWillChange.send()
    }
    
    public func toggleMute(for pid: pid_t) {
        if let proc = displayProcesses.first(where: { $0.pid == pid }) {
            toggleMute(for: proc)
        } else {
            audioEngine.setMute(for: pid, isMuted: true)
        }
    }
    
    public func updateMasterVolume(_ volume: Float) {
        let clamped = max(0.0, min(2.0, volume))
        self.masterVolume = clamped
        if clamped > 0 && isMasterMuted {
            isMasterMuted = false
            audioEngine.setMasterMute(false)
        }
        audioEngine.setMasterVolume(min(1.0, clamped))
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
    
    public func setOutputDevice(for process: AudioProcess, device: AudioDevice?) {
        let targetBundleID = process.bundleIdentifier
        let pid = process.pid
        let deviceUID = device?.uid
        
        if let index = processes.firstIndex(where: { $0.pid == pid || ($0.bundleIdentifier != nil && $0.bundleIdentifier == targetBundleID) }) {
            processes[index].outputDeviceUID = deviceUID
        }
        
        if let bundleID = targetBundleID {
            if let devUID = deviceUID {
                inMemorySavedAppOutputDevices[bundleID] = devUID
            } else {
                inMemorySavedAppOutputDevices.removeValue(forKey: bundleID)
            }
            preferencesSaveSubject.send()
            audioEngine.setOutputDevice(forBundleID: bundleID, deviceUID: deviceUID)
        }
        
        if pid > 0 {
            audioEngine.setOutputDevice(for: pid, deviceUID: deviceUID)
        }
        objectWillChange.send()
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
        systemPermissions.requestPermissions()
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
