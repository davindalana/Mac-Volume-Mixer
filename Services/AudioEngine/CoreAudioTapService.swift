import Foundation
import AppKit
import CoreAudio
import AudioToolbox
import Combine
import os.log

/// Implementasi konkret `AudioEngineProtocol` menggunakan CoreAudio Process Audio Tap (macOS 14.2+)
/// dan AudioHardware HAL C-API untuk manajemen volume per aplikasi serta perangkat output.
public final class CoreAudioTapService: AudioEngineProtocol, @unchecked Sendable {
    // MARK: - Properties
    private let logger = Logger(subsystem: "com.macvolumemixer.app", category: "CoreAudioTapService")
    
    /// Service untuk memantau lifecycle aplikasi
    private let processWatcher: ProcessWatcher
    
    /// Real-time DSP mixer engine untuk mixing stream audio per proses
    private let mixerEngine = RealtimeMixerEngine()
    
    /// Dictionary menyimpan AudioObjectID Tap per Process ID (PID)
    private var processTaps: [pid_t: AudioObjectID] = [:]
    
    /// Dictionary menyimpan AudioObjectID Tap per App Key (BundleID)
    private var appTaps: [String: AudioObjectID] = [:]
    
    /// Menyimpan gain / volume per PID (0.0 ... 1.0)
    private var processVolumes: [pid_t: Float] = [:]
    
    /// Menyimpan gain / volume per App Key
    private var appVolumes: [String: Float] = [:]
    
    /// Menyimpan status mute per PID
    private var processMutes: [pid_t: Bool] = [:]
    
    /// Menyimpan status mute per App Key
    private var appMutes: [String: Bool] = [:]
    
    /// State thread-safe lock
    private let stateLock = NSLock()
    
    /// Flag status aktif monitoring
    private var isMonitoringActive = false
    
    /// Listener blocks references untuk unregistering saat deinit
    private var propertyListenerBlocks: [(address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Publishers
    private let activeProcessesSubject = CurrentValueSubject<[AudioProcess], Never>([])
    private let outputDevicesSubject = CurrentValueSubject<[AudioDevice], Never>([])
    private let masterVolumeSubject = CurrentValueSubject<Float, Never>(1.0)
    private let masterMuteSubject = CurrentValueSubject<Bool, Never>(false)
    
    public var activeProcessesPublisher: AnyPublisher<[AudioProcess], Never> {
        activeProcessesSubject.eraseToAnyPublisher()
    }
    
    public var outputDevicesPublisher: AnyPublisher<[AudioDevice], Never> {
        outputDevicesSubject.eraseToAnyPublisher()
    }
    
    public var masterVolumePublisher: AnyPublisher<Float, Never> {
        masterVolumeSubject.eraseToAnyPublisher()
    }
    
    public var masterMutePublisher: AnyPublisher<Bool, Never> {
        masterMuteSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initializer
    public init(processWatcher: ProcessWatcher = ProcessWatcher()) {
        self.processWatcher = processWatcher
        
        // Mengamati notifikasi aplikasi dibuka/ditutup dari ProcessWatcher
        processWatcher.onAppsChanged
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.refreshAudioProcesses()
            }
            .store(in: &cancellables)
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - AudioEngineProtocol Lifecycle
    
    public func startMonitoring() {
        stateLock.lock()
        guard !isMonitoringActive else {
            stateLock.unlock()
            return
        }
        isMonitoringActive = true
        stateLock.unlock()
        
        logger.info("Memulai CoreAudio Tap monitoring...")
        
        // Registrasi listener hardware CoreAudio
        registerSystemAudioListeners()
        
        // Muat awal daftar perangkat dan proses
        refreshOutputDevices()
        refreshMasterVolume()
        refreshAudioProcesses()
    }
    
    public func stopMonitoring() {
        stateLock.lock()
        guard isMonitoringActive else {
            stateLock.unlock()
            return
        }
        isMonitoringActive = false
        
        // Hentikan Realtime Mixer Engine
        mixerEngine.stop()
        
        // Hancurkan semua tap yang sedang aktif
        if #available(macOS 14.2, *) {
            for (_, tapID) in appTaps {
                _ = AudioHardwareDestroyProcessTap(tapID)
            }
        }
        appTaps.removeAll()
        for (pid, tapID) in processTaps {
            destroyProcessTap(tapID: tapID, for: pid)
        }
        processTaps.removeAll()
        stateLock.unlock()
        
        unregisterSystemAudioListeners()
        logger.info("CoreAudio Tap monitoring dihentikan.")
    }
    
    // MARK: - Volume & Mute per Process & Bundle ID
    
    public func setVolume(for pid: pid_t, volume: Float) {
        let info = processWatcher.appInfo(for: pid)
        setVolumeInternal(pid: pid, bundleID: info.bundleID, appName: info.name, volume: volume)
    }
    
    public func setVolume(forBundleID bundleID: String, volume: Float) {
        let runningPID = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
        let appName = appNameFromBundleID(bundleID)
        setVolumeInternal(pid: runningPID, bundleID: bundleID, appName: appName, volume: volume)
    }
    
    private func setVolumeInternal(pid: pid_t?, bundleID: String?, appName: String?, volume: Float) {
        let clampedVolume = max(0.0, min(2.0, volume))
        let key = bundleID?.lowercased() ?? (pid != nil ? "pid_\(pid!)" : "unknown")
        
        stateLock.lock()
        if let pid = pid {
            processVolumes[pid] = clampedVolume
        }
        appVolumes[key] = clampedVolume
        let isMuted = (pid != nil ? processMutes[pid!] : nil) ?? appMutes[key] ?? false
        stateLock.unlock()
        
        let targetObjects = allAudioObjectIDs(for: pid, bundleID: bundleID)
        let defUID = getDefaultOutputDeviceUID()
        
        // 1. Terapkan DSP Realtime Mixing Audio Engine (Mengatur PCM volume level 0.0 ... 1.0)
        mixerEngine.setVolume(
            for: key,
            targetObjects: targetObjects,
            defaultDeviceUID: defUID,
            volume: clampedVolume,
            isMuted: isMuted
        )
        
        // 2. Terapkan penyesuaian volume aplikasi secara native jika didukung
        adjustAppVolumeNative(pid: pid, bundleID: bundleID, appName: appName, volume: clampedVolume, isMuted: isMuted)
        
        if let pid = pid {
            updatePublishedProcess(pid: pid) { process in
                process.volume = clampedVolume
            }
        }
    }
    
    public func setMute(for pid: pid_t, isMuted: Bool) {
        let info = processWatcher.appInfo(for: pid)
        setMuteInternal(pid: pid, bundleID: info.bundleID, appName: info.name, isMuted: isMuted)
    }
    
    public func setMute(forBundleID bundleID: String, isMuted: Bool) {
        let runningPID = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
        let appName = appNameFromBundleID(bundleID)
        setMuteInternal(pid: runningPID, bundleID: bundleID, appName: appName, isMuted: isMuted)
    }
    
    private func setMuteInternal(pid: pid_t?, bundleID: String?, appName: String?, isMuted: Bool) {
        let key = bundleID?.lowercased() ?? (pid != nil ? "pid_\(pid!)" : "unknown")
        
        stateLock.lock()
        if let pid = pid {
            processMutes[pid] = isMuted
        }
        appMutes[key] = isMuted
        let volume = (pid != nil ? processVolumes[pid!] : nil) ?? appVolumes[key] ?? 1.0
        stateLock.unlock()
        
        let targetObjects = allAudioObjectIDs(for: pid, bundleID: bundleID)
        let defUID = getDefaultOutputDeviceUID()
        
        // 1. Terapkan DSP Realtime Mixing Mute
        mixerEngine.setVolume(
            for: key,
            targetObjects: targetObjects,
            defaultDeviceUID: defUID,
            volume: volume,
            isMuted: isMuted
        )
        
        // 2. Terapkan mute di level native aplikasi
        adjustAppVolumeNative(pid: pid, bundleID: bundleID, appName: appName, volume: volume, isMuted: isMuted)
        
        if let pid = pid {
            updatePublishedProcess(pid: pid) { process in
                process.isMuted = isMuted
            }
        }
    }
    
    // MARK: - CoreAudio Process Tap (macOS 14.2+)
    
    /// Mengumpulkan seluruh AudioObjectID yang relevan untuk suatu aplikasi (termasuk helper / GPU media)
    private func allAudioObjectIDs(for pid: pid_t?, bundleID: String?) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
        guard status == noErr else { return [] }
        
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var objIDs = [AudioObjectID](repeating: 0, count: count)
        let getStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &objIDs)
        guard getStatus == noErr else { return [] }
        
        var targetBundleID = bundleID?.lowercased() ?? ""
        if targetBundleID.isEmpty, let pid = pid, pid > 0 {
            let info = processWatcher.appInfo(for: pid)
            targetBundleID = info.bundleID?.lowercased() ?? ""
        }
        
        var result = Set<AudioObjectID>()
        for id in objIDs {
            var pidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var objPID: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            _ = AudioObjectGetPropertyData(id, &pidAddr, 0, nil, &pidSize, &objPID)
            
            var bAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfBundle: Unmanaged<CFString>? = nil
            var cfSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            _ = AudioObjectGetPropertyData(id, &bAddr, 0, nil, &cfSize, &cfBundle)
            let objBID = (cfBundle?.takeRetainedValue() as String?)?.lowercased() ?? ""
            
            if let pid = pid, pid > 0 && objPID == pid {
                result.insert(id)
            }
            
            if !targetBundleID.isEmpty {
                if targetBundleID.contains("safari") {
                    if objBID.contains("safari") || objBID.contains("webkit") {
                        result.insert(id)
                    }
                } else if targetBundleID.contains("whatsapp") {
                    if objBID.contains("whatsapp") {
                        result.insert(id)
                    }
                } else if targetBundleID.contains("chrome") {
                    if objBID.contains("chrome") {
                        result.insert(id)
                    }
                } else if !objBID.isEmpty && (objBID == targetBundleID || objBID.hasPrefix(targetBundleID + ".")) {
                    result.insert(id)
                }
            }
        }
        
        if result.isEmpty, let pid = pid, pid > 0, let directObj = translatePIDToProcessObject(pid: pid) {
            result.insert(directObj)
        }
        
        return Array(result)
    }
    
    /// Menginisialisasi Process Tap untuk PID tertentu
    private func initializeProcessTapIfNeeded(for pid: pid_t) {
        guard #available(macOS 14.2, *) else { return }
        
        stateLock.lock()
        if processTaps[pid] != nil {
            stateLock.unlock()
            return
        }
        stateLock.unlock()
        
        let targetObjects = allAudioObjectIDs(for: pid, bundleID: nil)
        guard !targetObjects.isEmpty else { return }
        
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: targetObjects)
        tapDescription.name = "MixerTap_\(pid)"
        tapDescription.isPrivate = true
        
        stateLock.lock()
        let isMuted = (processMutes[pid] ?? false) || ((processVolumes[pid] ?? 1.0) == 0.0)
        stateLock.unlock()
        
        tapDescription.muteBehavior = isMuted ? CATapMuteBehavior.muted : CATapMuteBehavior.unmuted
        
        var tapID: AudioObjectID = 0
        let status = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        
        if status == noErr && tapID != 0 {
            stateLock.lock()
            processTaps[pid] = tapID
            stateLock.unlock()
            logger.info("Berhasil membuat Process Tap untuk PID: \(pid), TapID: \(tapID)")
        }
    }
    
    /// Menghancurkan audio tap saat aplikasi ditutup atau monitoring berhenti
    private func destroyProcessTap(tapID: AudioObjectID, for pid: pid_t) {
        guard #available(macOS 14.2, *) else { return }
        let status = AudioHardwareDestroyProcessTap(tapID)
        if status == noErr {
            logger.info("Berhasil menghancurkan TapID: \(tapID) untuk PID: \(pid)")
        } else {
            logger.error("Gagal menghancurkan TapID: \(tapID): \(self.formatOSStatus(status))")
        }
    }
    
    /// Memperbarui status mute Process Tap dengan menghancurkan dan membuat ulang tap
    private func updateProcessTapMute(for pid: pid_t?, bundleID: String?, isMuted: Bool) {
        guard #available(macOS 14.2, *) else { return }
        
        let key = bundleID?.lowercased() ?? (pid != nil ? "pid_\(pid!)" : "unknown")
        
        stateLock.lock()
        let oldTapID = appTaps[key] ?? (pid != nil ? processTaps[pid!] : nil)
        stateLock.unlock()
        
        if let tapID = oldTapID {
            _ = AudioHardwareDestroyProcessTap(tapID)
            stateLock.lock()
            appTaps.removeValue(forKey: key)
            if let pid = pid { processTaps.removeValue(forKey: pid) }
            stateLock.unlock()
        }
        
        guard isMuted else {
            logger.info("App \(key) unmuted - hardware tap destroyed.")
            return
        }
        
        let targetObjects = allAudioObjectIDs(for: pid, bundleID: bundleID)
        guard !targetObjects.isEmpty else {
            logger.debug("Tidak ada target audio object untuk di-mute pada key: \(key)")
            return
        }
        
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: targetObjects)
        tapDescription.name = "MixerTap_\(key)"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .muted
        
        var newTapID: AudioObjectID = 0
        let status = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        if status == noErr && newTapID != 0 {
            stateLock.lock()
            appTaps[key] = newTapID
            if let pid = pid { processTaps[pid] = newTapID }
            stateLock.unlock()
            logger.info("Process Tap MUTED sukses untuk \(key), targets=\(targetObjects), tapID=\(newTapID)")
        } else {
            logger.error("Gagal membuat muted tap untuk \(key): \(self.formatOSStatus(status))")
        }
    }
    
    /// Mengatur volume aplikasi secara native melalui AppleScript / Scripting Bridge
    private func adjustAppVolumeNative(pid: pid_t?, bundleID: String?, appName: String?, volume: Float, isMuted: Bool) {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            let bID = (bundleID ?? "").lowercased()
            let name = (appName ?? "").lowercased()
            let volPercent = isMuted ? 0 : min(100, Int(round(volume * 100)))
            let effectiveVolume = isMuted ? 0.0 : volume
            // HTMLMediaElement e.volume hanya menerima rentang 0.0 ... 1.0, jika > 1.0 akan throw exception
            let jsVolume = isMuted ? 0.0 : min(1.0, max(0.0, volume))
            
            var script: String? = nil
            
            if bID == "com.spotify.client" || name.contains("spotify") {
                script = "tell application \"Spotify\" to set sound volume to \(volPercent)"
            } else if bID == "com.apple.music" || name == "music" {
                script = "tell application \"Music\" to set sound volume to \(volPercent)"
            } else if bID == "org.videolan.vlc" || name.contains("vlc") {
                let vlcVol = isMuted ? 0 : Int(round(volume * 512))
                script = "tell application \"VLC\" to set volume \(vlcVol)"
            } else if bID == "com.apple.quicktimeplayerx" || name.contains("quicktime") {
                script = "tell application \"QuickTime Player\" to if (count of documents) > 0 then set volume of front document to \(jsVolume)"
            } else if bID == "com.apple.safari" || name.contains("safari") {
                script = """
                tell application "Safari"
                    if (count of windows) > 0 then
                        try
                            tell current tab of front window
                                do JavaScript "document.querySelectorAll('video, audio').forEach(e => { e.volume = \(jsVolume); e.muted = \(isMuted ? "true" : "false"); });"
                            end tell
                        end try
                    end if
                end tell
                """
            } else if bID.contains("chrome") || bID.contains("browser") || bID.contains("brave") || bID.contains("edgemac") || bID.contains("firefox") || name.contains("chrome") {
                let targetAppName = appName?.isEmpty == false ? appName! : "Google Chrome"
                script = """
                tell application "\(targetAppName)"
                    if (count of windows) > 0 then
                        try
                            tell active tab of front window
                                execute javascript "document.querySelectorAll('video, audio').forEach(e => { e.volume = \(jsVolume); e.muted = \(isMuted ? "true" : "false"); });"
                            end tell
                        end try
                    end if
                end tell
                """
            } else if bID.contains("whatsapp") || name.contains("whatsapp") {
                self.updateProcessTapMute(for: pid, bundleID: bundleID, isMuted: isMuted || effectiveVolume == 0.0)
            }
            
            if let scriptSource = script {
                var error: NSDictionary?
                if let appleScript = NSAppleScript(source: scriptSource) {
                    appleScript.executeAndReturnError(&error)
                }
            }
        }
    }
    
    private func appNameFromBundleID(_ bundleID: String) -> String {
        if bundleID.lowercased().contains("finder") { return "Finder" }
        if bundleID.lowercased().contains("safari") { return "Safari" }
        if bundleID.lowercased().contains("music") { return "Music" }
        if bundleID.lowercased().contains("whatsapp") { return "WhatsApp" }
        if bundleID.lowercased().contains("chrome") { return "Google Chrome" }
        if bundleID.lowercased().contains("spotify") { return "Spotify" }
        return bundleID.components(separatedBy: ".").last?.capitalized ?? bundleID
    }
    
    /// Translasi PID ke AudioObjectID Process Object milik CoreAudio
    private func translatePIDToProcessObject(pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var targetPID = pid
        var processObjectID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &targetPID,
            &size,
            &processObjectID
        )
        
        if status == noErr && processObjectID != kAudioObjectUnknown {
            return processObjectID
        }
        return nil
    }
    
    // MARK: - Process Discovery & Audit
    
    /// Menyegarkan daftar aplikasi yang terdeteksi menghasilkan audio
    public func refreshAudioProcesses() {
        var detectedProcesses: [AudioProcess] = []
        
        // 1. Ambil seluruh proses dari CoreAudio hardware
        let audioProcesses = fetchCoreAudioProcessList()
        
        // 1. Cek apakah ada proses WebKit GPU / Helper yang sedang memutar audio untuk Safari atau WhatsApp
        var isSafariAudioActive = false
        var isWhatsAppAudioActive = false
        for item in audioProcesses {
            let info = processWatcher.appInfo(for: item.pid)
            let bID = (info.bundleID ?? "").lowercased()
            let name = info.name.lowercased()
            if (bID.contains("webkit") || name.contains("safari graphics and media")) && item.isRunningOutput {
                isSafariAudioActive = true
            }
            if bID.contains("whatsapp") && item.isRunningOutput {
                isWhatsAppAudioActive = true
            }
        }
        
        for item in audioProcesses {
            let pid = item.pid
            let isRunningOutput = item.isRunningOutput
            
            // Dapatkan metadata aplikasi dari ProcessWatcher
            let info = processWatcher.appInfo(for: pid)
            
            // Filter: prioritaskan aplikasi yang memiliki nama atau bundleID
            if let runningApp = NSRunningApplication(processIdentifier: pid), runningApp.activationPolicy == .regular {
                stateLock.lock()
                let currentVolume = processVolumes[pid] ?? 1.0
                let currentMute = processMutes[pid] ?? false
                stateLock.unlock()
                
                let isSafari = (info.bundleID?.lowercased().contains("safari") == true || info.name.lowercased().contains("safari"))
                let isWhatsApp = (info.bundleID?.lowercased().contains("whatsapp") == true || info.name.lowercased().contains("whatsapp"))
                let hasAudio = isRunningOutput || (isSafari && isSafariAudioActive) || (isWhatsApp && isWhatsAppAudioActive)
                let cleanName = info.name.replacingOccurrences(of: "\u{200E}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                
                let process = AudioProcess(
                    pid: pid,
                    appName: cleanName.isEmpty ? "Process \(pid)" : cleanName,
                    bundleIdentifier: info.bundleID,
                    icon: info.icon,
                    volume: currentVolume,
                    isMuted: currentMute,
                    isPlayingAudio: hasAudio
                )
                detectedProcesses.append(process)
                
                // Siapkan tap jika belum ada
                initializeProcessTapIfNeeded(for: pid)
            }
        }
        
        // 2. Tambahkan aplikasi berjalan umum jika list CoreAudio sedikit (untuk UX optimal)
        let regularApps = processWatcher.getRegularRunningApplications()
        for app in regularApps {
            let pid = app.processIdentifier
            if !detectedProcesses.contains(where: { $0.pid == pid }) {
                let info = processWatcher.appInfo(for: pid)
                stateLock.lock()
                let currentVolume = processVolumes[pid] ?? 1.0
                let currentMute = processMutes[pid] ?? false
                stateLock.unlock()
                
                let isSafari = (info.bundleID?.lowercased().contains("safari") == true || info.name.lowercased().contains("safari"))
                let isWhatsApp = (info.bundleID?.lowercased().contains("whatsapp") == true || info.name.lowercased().contains("whatsapp"))
                let hasAudio = (isSafari && isSafariAudioActive) || (isWhatsApp && isWhatsAppAudioActive)
                let cleanName = info.name.replacingOccurrences(of: "\u{200E}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                
                let process = AudioProcess(
                    pid: pid,
                    appName: cleanName.isEmpty ? "Process \(pid)" : cleanName,
                    bundleIdentifier: info.bundleID,
                    icon: info.icon,
                    volume: currentVolume,
                    isMuted: currentMute,
                    isPlayingAudio: hasAudio
                )
                detectedProcesses.append(process)
            }
        }
        
        // Fallback untuk Xcode Preview atau jika tidak ada aplikasi
        #if DEBUG
        if detectedProcesses.isEmpty || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            detectedProcesses = AudioProcess.mockList
        }
        #endif
        
        // Urutkan: aplikasi yang sedang bersuara di atas, lalu urut abjad
        detectedProcesses.sort {
            if $0.isPlayingAudio != $1.isPlayingAudio {
                return $0.isPlayingAudio && !$1.isPlayingAudio
            }
            return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
        }
        
        // Sinkronkan aplikasi yang memiliki volume tersimpan != 1.0 (attenuated atau boosted) atau di-mute ke RealtimeMixerEngine
        let defUID = self.getDefaultOutputDeviceUID()
        for p in detectedProcesses {
            if abs(p.volume - 1.0) > 0.001 || p.isMuted {
                let key = p.bundleIdentifier?.lowercased() ?? "pid_\(p.pid)"
                let targets = self.allAudioObjectIDs(for: p.pid, bundleID: p.bundleIdentifier)
                self.mixerEngine.setVolume(
                    for: key,
                    targetObjects: targets,
                    defaultDeviceUID: defUID,
                    volume: p.volume,
                    isMuted: p.isMuted
                )
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.activeProcessesSubject.send(detectedProcesses)
        }
    }
    
    private func fetchCoreAudioProcessList() -> [(pid: pid_t, isRunningOutput: Bool)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else { return [] }
        
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var processObjectIDs = [AudioObjectID](repeating: 0, count: count)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &processObjectIDs
        )
        guard status == noErr else { return [] }
        
        var results: [(pid: pid_t, isRunningOutput: Bool)] = []
        for objID in processObjectIDs {
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            let pidStatus = AudioObjectGetPropertyData(objID, &pidAddress, 0, nil, &pidSize, &pid)
            
            if pidStatus == noErr {
                var outputAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioProcessPropertyIsRunningOutput,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var isRunningOutput: UInt32 = 0
                var outputSize = UInt32(MemoryLayout<UInt32>.size)
                _ = AudioObjectGetPropertyData(objID, &outputAddress, 0, nil, &outputSize, &isRunningOutput)
                
                results.append((pid: pid, isRunningOutput: isRunningOutput != 0))
            }
        }
        return results
    }
    
    // MARK: - Master Volume & Output Devices
    
    public func getMasterVolume() -> Float {
        let defaultDeviceID = getDefaultOutputDeviceID()
        guard defaultDeviceID != kAudioObjectUnknown else { return 1.0 }
        
        var volume: Float32 = 1.0
        var propertySize = UInt32(MemoryLayout<Float32>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            defaultDeviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &volume
        )
        
        return status == noErr ? volume : 1.0
    }
    
    public func setMasterVolume(_ volume: Float) {
        let clampedVolume = max(0.0, min(1.0, volume))
        let defaultDeviceID = getDefaultOutputDeviceID()
        guard defaultDeviceID != kAudioObjectUnknown else { return }
        
        var volToSet = Float32(clampedVolume)
        let propertySize = UInt32(MemoryLayout<Float32>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        _ = AudioObjectSetPropertyData(
            defaultDeviceID,
            &propertyAddress,
            0,
            nil,
            propertySize,
            &volToSet
        )
        
        masterVolumeSubject.send(clampedVolume)
    }
    
    public func getMasterMute() -> Bool {
        let defaultDeviceID = getDefaultOutputDeviceID()
        guard defaultDeviceID != kAudioObjectUnknown else { return false }
        
        var isMuted: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            defaultDeviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &isMuted
        )
        
        return status == noErr ? (isMuted != 0) : false
    }
    
    public func setMasterMute(_ isMuted: Bool) {
        let defaultDeviceID = getDefaultOutputDeviceID()
        guard defaultDeviceID != kAudioObjectUnknown else { return }
        
        var muteVal: UInt32 = isMuted ? 1 : 0
        let propertySize = UInt32(MemoryLayout<UInt32>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        _ = AudioObjectSetPropertyData(
            defaultDeviceID,
            &propertyAddress,
            0,
            nil,
            propertySize,
            &muteVal
        )
        
        masterMuteSubject.send(isMuted)
    }
    
    public func getOutputDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else { return [] }
        
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }
        
        let defaultID = getDefaultOutputDeviceID()
        var results: [AudioDevice] = []
        
        for id in deviceIDs {
            // Periksa apakah perangkat memiliki output audio stream
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            let streamStatus = AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &streamSize)
            
            if streamStatus == noErr && streamSize > 0 {
                // Ambil Nama Perangkat
                var nameAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyDeviceNameCFString,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var nameCF: CFString? = nil
                var nameSize = UInt32(MemoryLayout<CFString?>.size)
                _ = withUnsafeMutablePointer(to: &nameCF) { ptr in
                    AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, ptr)
                }
                
                // Ambil UID Perangkat
                var uidAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyDeviceUID,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var uidCF: CFString? = nil
                var uidSize = UInt32(MemoryLayout<CFString?>.size)
                _ = withUnsafeMutablePointer(to: &uidCF) { ptr in
                    AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, ptr)
                }
                
                let name = (nameCF as String?) ?? "Output Device"
                let uid = (uidCF as String?) ?? "\(id)"
                let isDefault = (id == defaultID)
                
                results.append(AudioDevice(
                    id: id,
                    uid: uid,
                    name: name,
                    isDefault: isDefault,
                    volume: getMasterVolume(),
                    isMuted: getMasterMute()
                ))
            }
        }
        
        #if DEBUG
        if results.isEmpty {
            results = AudioDevice.mockList
        }
        #endif
        
        return results
    }
    
    public func setDefaultOutputDevice(_ device: AudioDevice) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var newID = device.id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &newID
        )
        
        if status == noErr {
            refreshOutputDevices()
            refreshMasterVolume()
        }
    }
    
    // MARK: - Internal Helper Methods
    
    private func getDefaultOutputDeviceID() -> AudioDeviceID {
        var defaultID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &defaultID
        )
        return status == noErr ? defaultID : kAudioObjectUnknown
    }
    
    private func getDefaultOutputDeviceUID() -> String {
        let defID = getDefaultOutputDeviceID()
        guard defID != kAudioObjectUnknown else { return "BuiltInSpeakerDevice" }
        var devUIDAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devUIDCF: CFString? = nil
        var devUIDSize = UInt32(MemoryLayout<CFString?>.size)
        _ = withUnsafeMutablePointer(to: &devUIDCF) { ptr in
            AudioObjectGetPropertyData(defID, &devUIDAddr, 0, nil, &devUIDSize, ptr)
        }
        return (devUIDCF as String?) ?? "BuiltInSpeakerDevice"
    }
    
    private func refreshOutputDevices() {
        let devices = getOutputDevices()
        DispatchQueue.main.async { [weak self] in
            self?.outputDevicesSubject.send(devices)
        }
    }
    
    private func refreshMasterVolume() {
        let vol = getMasterVolume()
        let isMuted = getMasterMute()
        DispatchQueue.main.async { [weak self] in
            self?.masterVolumeSubject.send(vol)
            self?.masterMuteSubject.send(isMuted)
        }
    }
    
    private func updatePublishedProcess(pid: pid_t, modifier: (inout AudioProcess) -> Void) {
        var current = activeProcessesSubject.value
        if let idx = current.firstIndex(where: { $0.pid == pid }) {
            modifier(&current[idx])
            DispatchQueue.main.async { [weak self] in
                self?.activeProcessesSubject.send(current)
            }
        }
    }
    
    // MARK: - CoreAudio Hardware Listeners
    
    private func registerSystemAudioListeners() {
        // 1. Listener untuk default output device
        var defaultDevAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let devBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refreshOutputDevices()
            self?.refreshMasterVolume()
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDevAddress, DispatchQueue.main, devBlock) == noErr {
            propertyListenerBlocks.append((defaultDevAddress, devBlock))
        }
        
        // 2. Listener untuk daftar proses audio sistem
        var processListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let processBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refreshAudioProcesses()
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &processListAddress, DispatchQueue.main, processBlock) == noErr {
            propertyListenerBlocks.append((processListAddress, processBlock))
        }
    }
    
    private func unregisterSystemAudioListeners() {
        for item in propertyListenerBlocks {
            var addr = item.address
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &addr,
                DispatchQueue.main,
                item.block
            )
        }
        propertyListenerBlocks.removeAll()
    }
    
    private func formatOSStatus(_ status: OSStatus) -> String {
        let n = Int(status)
        let chars: [CChar] = [
            CChar((n >> 24) & 0xFF),
            CChar((n >> 16) & 0xFF),
            CChar((n >> 8) & 0xFF),
            CChar(n & 0xFF),
            0
        ]
        if chars.allSatisfy({ $0 >= 32 && $0 <= 126 }) {
            return String(cString: chars)
        }
        return "\(status)"
    }
}
