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
    
    /// Menyimpan gain / volume per PID (0.0 ... 1.0)
    private var processVolumes: [pid_t: Float] = [:]
    
    /// Menyimpan gain / volume per App Key
    private var appVolumes: [String: Float] = [:]
    
    /// Menyimpan status mute per PID
    private var processMutes: [pid_t: Bool] = [:]
    
    /// Menyimpan status mute per App Key
    private var appMutes: [String: Bool] = [:]
    
    /// Menyimpan output device UID per PID dan per App Key
    private var processOutputDevices: [pid_t: String] = [:]
    private var appOutputDevices: [String: String] = [:]
    
    /// Cache mapping target AudioObjectIDs per BundleID dan PID untuk menghindari synchronous CoreAudio HAL query saat sliding
    private var cachedAudioObjectsByBundleID: [String: [AudioObjectID]] = [:]
    private var cachedAudioObjectsByPID: [pid_t: [AudioObjectID]] = [:]
    private var cachedDefaultOutputDeviceUID: String = ""
    
    /// Debounced AppleScript work item agar tidak terjadi blocking IPC pada player legacy (Spotify/Music)
    private var pendingAppleScriptWorkItem: DispatchWorkItem?
    private let appleScriptQueue = DispatchQueue(label: "com.macvolumemixer.applescript", qos: .utility)
    
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
        
        // Mengamati notifikasi aplikasi dibuka/ditutup dari ProcessWatcher dengan debounce 300ms
        processWatcher.onAppsChanged
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
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
        
        let targetObjects = getTargetAudioObjects(for: pid, bundleID: bundleID)
        let customDeviceUID = (pid != nil ? processOutputDevices[pid!] : nil) ?? appOutputDevices[key]
        let targetDeviceUID = customDeviceUID ?? getCachedDefaultOutputDeviceUID()
        
        // 1. Terapkan DSP Realtime Mixing Audio Engine (Mengatur PCM volume level 0.0 ... 2.0 & Output Device)
        mixerEngine.setVolume(
            for: key,
            targetObjects: targetObjects,
            defaultDeviceUID: targetDeviceUID,
            volume: clampedVolume,
            isMuted: isMuted
        )
        
        // 2. Debounced native adjustments (hanya untuk legacy AppleScript Spotify / Music)
        adjustAppVolumeNativeDebounced(pid: pid, bundleID: bundleID, appName: appName, volume: clampedVolume, isMuted: isMuted)
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
        
        let targetObjects = getTargetAudioObjects(for: pid, bundleID: bundleID)
        let customDeviceUID = (pid != nil ? processOutputDevices[pid!] : nil) ?? appOutputDevices[key]
        let targetDeviceUID = customDeviceUID ?? getCachedDefaultOutputDeviceUID()
        
        // 1. Terapkan DSP Realtime Mixing Mute & Output Device
        mixerEngine.setVolume(
            for: key,
            targetObjects: targetObjects,
            defaultDeviceUID: targetDeviceUID,
            volume: volume,
            isMuted: isMuted
        )
        
        // 2. Debounced native adjustments
        adjustAppVolumeNativeDebounced(pid: pid, bundleID: bundleID, appName: appName, volume: volume, isMuted: isMuted)
    }
    
    public func setOutputDevice(for pid: pid_t, deviceUID: String?) {
        let info = processWatcher.appInfo(for: pid)
        setOutputDeviceInternal(pid: pid, bundleID: info.bundleID, appName: info.name, deviceUID: deviceUID)
    }
    
    public func setOutputDevice(forBundleID bundleID: String, deviceUID: String?) {
        let runningPID = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
        let appName = appNameFromBundleID(bundleID)
        setOutputDeviceInternal(pid: runningPID, bundleID: bundleID, appName: appName, deviceUID: deviceUID)
    }
    
    private func setOutputDeviceInternal(pid: pid_t?, bundleID: String?, appName: String?, deviceUID: String?) {
        let key = bundleID?.lowercased() ?? (pid != nil ? "pid_\(pid!)" : "unknown")
        
        stateLock.lock()
        if let pid = pid {
            if let dev = deviceUID {
                processOutputDevices[pid] = dev
            } else {
                processOutputDevices.removeValue(forKey: pid)
            }
        }
        if let dev = deviceUID {
            appOutputDevices[key] = dev
        } else {
            appOutputDevices.removeValue(forKey: key)
        }
        let volume = (pid != nil ? processVolumes[pid!] : nil) ?? appVolumes[key] ?? 1.0
        let isMuted = (pid != nil ? processMutes[pid!] : nil) ?? appMutes[key] ?? false
        stateLock.unlock()
        
        let targetObjects = getTargetAudioObjects(for: pid, bundleID: bundleID)
        let targetDeviceUID = deviceUID ?? getCachedDefaultOutputDeviceUID()
        
        mixerEngine.setVolume(
            for: key,
            targetObjects: targetObjects,
            defaultDeviceUID: targetDeviceUID,
            volume: volume,
            isMuted: isMuted
        )
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
    
    /// Mengambil target AudioObjectID dari cache atau HAL untuk performa instan (0ms latency)
    private func getTargetAudioObjects(for pid: pid_t?, bundleID: String?) -> [AudioObjectID] {
        stateLock.lock()
        if let bID = bundleID?.lowercased(), let cached = cachedAudioObjectsByBundleID[bID], !cached.isEmpty {
            stateLock.unlock()
            return cached
        }
        if let pid = pid, pid > 0, let cached = cachedAudioObjectsByPID[pid], !cached.isEmpty {
            stateLock.unlock()
            return cached
        }
        stateLock.unlock()
        
        let objs = allAudioObjectIDs(for: pid, bundleID: bundleID)
        stateLock.lock()
        if let bID = bundleID?.lowercased() {
            cachedAudioObjectsByBundleID[bID] = objs
        }
        if let pid = pid, pid > 0 {
            cachedAudioObjectsByPID[pid] = objs
        }
        stateLock.unlock()
        return objs
    }
    
    /// Mengambil UID Default Output Device dari cache
    private func getCachedDefaultOutputDeviceUID() -> String {
        stateLock.lock()
        let cached = cachedDefaultOutputDeviceUID
        stateLock.unlock()
        if !cached.isEmpty { return cached }
        let defUID = getDefaultOutputDeviceUID()
        stateLock.lock()
        cachedDefaultOutputDeviceUID = defUID
        stateLock.unlock()
        return defUID
    }
    
    /// Mengatur volume aplikasi legacy (Spotify / Music) secara debounced agar tidak memblokir UI slider
    private func adjustAppVolumeNativeDebounced(pid: pid_t?, bundleID: String?, appName: String?, volume: Float, isMuted: Bool) {
        let bID = (bundleID ?? "").lowercased()
        let name = (appName ?? "").lowercased()
        
        // Hanya jalankan AppleScript untuk player legacy yang tidak menggunakan CoreAudio tap langsung
        let isLegacyPlayer = bID == "com.spotify.client" || name.contains("spotify") ||
                             bID == "com.apple.music" || name == "music" ||
                             bID == "org.videolan.vlc" || name.contains("vlc") ||
                             bID == "com.apple.quicktimeplayerx" || name.contains("quicktime")
        
        guard isLegacyPlayer else { return }
        
        stateLock.lock()
        pendingAppleScriptWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard self != nil else { return }
            let volPercent = isMuted ? 0 : min(100, Int(round(volume * 100)))
            var script: String? = nil
            
            if bID == "com.spotify.client" || name.contains("spotify") {
                script = "tell application \"Spotify\" to set sound volume to \(volPercent)"
            } else if bID == "com.apple.music" || name == "music" {
                script = "tell application \"Music\" to set sound volume to \(volPercent)"
            } else if bID == "org.videolan.vlc" || name.contains("vlc") {
                let vlcVol = isMuted ? 0 : Int(round(volume * 512))
                script = "tell application \"VLC\" to set volume \(vlcVol)"
            } else if bID == "com.apple.quicktimeplayerx" || name.contains("quicktime") {
                let jsVolume = isMuted ? 0.0 : min(1.0, max(0.0, volume))
                script = "tell application \"QuickTime Player\" to if (count of documents) > 0 then set volume of front document to \(jsVolume)"
            }
            
            if let scriptSource = script {
                var error: NSDictionary?
                if let appleScript = NSAppleScript(source: scriptSource) {
                    appleScript.executeAndReturnError(&error)
                }
            }
        }
        
        pendingAppleScriptWorkItem = workItem
        stateLock.unlock()
        
        appleScriptQueue.asyncAfter(deadline: .now() + .milliseconds(250), execute: workItem)
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
            if bID.contains("webkit") || name.contains("safari graphics and media") || bID.contains("safari") {
                isSafariAudioActive = true
            }
            if bID.contains("whatsapp") && (item.isRunningOutput || audioProcesses.count > 0) {
                isWhatsAppAudioActive = true
            }
        }
        
        // Helper untuk membuat AudioProcess yang telah tervalidasi
        let buildProcess: (pid_t, Bool) -> AudioProcess? = { [weak self] pid, isRunningOutput in
            guard let self = self else { return nil }
            let info = self.processWatcher.appInfo(for: pid)
            let cleanName = info.name.replacingOccurrences(of: "\u{200E}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let rawBID = info.bundleID, !rawBID.isEmpty,
                  !cleanName.isEmpty,
                  !cleanName.lowercased().hasPrefix("process"),
                  !cleanName.lowercased().contains("helper"),
                  let icon = info.icon else {
                return nil
            }
            
            let lowerBID = rawBID.lowercased()
            let excludedKeywords = ["corespeech", "mediaremote", "audiomxd", "controlcenter", "universalaccessd", "powerchime", "webkit", "helper", "xpc", "systemstat", "perfpower"]
            if excludedKeywords.contains(where: { lowerBID.contains($0) }) {
                return nil
            }
            
            if let runningApp = NSRunningApplication(processIdentifier: pid), runningApp.activationPolicy != .regular {
                return nil
            }
            
            self.stateLock.lock()
            let currentVolume = self.processVolumes[pid] ?? 1.0
            let currentMute = self.processMutes[pid] ?? false
            let currentDeviceUID = self.processOutputDevices[pid] ?? self.appOutputDevices[lowerBID]
            self.stateLock.unlock()
            
            let isSafari = lowerBID.contains("safari") || cleanName.lowercased().contains("safari")
            let isWhatsApp = lowerBID.contains("whatsapp") || cleanName.lowercased().contains("whatsapp")
            let hasAudio = isRunningOutput || (isSafari && isSafariAudioActive) || (isWhatsApp && isWhatsAppAudioActive)
            
            return AudioProcess(
                pid: pid,
                appName: cleanName,
                bundleIdentifier: info.bundleID,
                icon: icon,
                volume: currentVolume,
                isMuted: currentMute,
                isPlayingAudio: hasAudio,
                outputDeviceUID: currentDeviceUID
            )
        }
        
        for item in audioProcesses {
            if let process = buildProcess(item.pid, item.isRunningOutput) {
                detectedProcesses.append(process)
            }
        }
        
        // 2. Tambahkan aplikasi berjalan reguler jika belum terdaftar
        let regularApps = processWatcher.getRegularRunningApplications()
        for app in regularApps {
            let pid = app.processIdentifier
            if !detectedProcesses.contains(where: { $0.pid == pid }) {
                if let process = buildProcess(pid, false) {
                    detectedProcesses.append(process)
                }
            }
        }
        
        // Pre-populasikan cache target objects untuk pencarian 0ms saat volume diubah
        let defUID = self.getDefaultOutputDeviceUID()
        var newCacheBundleID: [String: [AudioObjectID]] = [:]
        var newCachePID: [pid_t: [AudioObjectID]] = [:]
        
        for p in detectedProcesses {
            let targets = self.allAudioObjectIDs(for: p.pid, bundleID: p.bundleIdentifier)
            if let bID = p.bundleIdentifier?.lowercased() {
                newCacheBundleID[bID] = targets
            }
            newCachePID[p.pid] = targets
            
            // Sinkronkan aplikasi yang memiliki volume tersimpan != 1.0 (attenuated atau boosted), di-mute, atau output device kustom ke RealtimeMixerEngine
            let customDev = p.outputDeviceUID
            if abs(p.volume - 1.0) > 0.001 || p.isMuted || (customDev != nil && customDev != defUID) {
                let key = p.bundleIdentifier?.lowercased() ?? "pid_\(p.pid)"
                let targetDev = customDev ?? defUID
                self.mixerEngine.setVolume(
                    for: key,
                    targetObjects: targets,
                    defaultDeviceUID: targetDev,
                    volume: p.volume,
                    isMuted: p.isMuted
                )
            }
        }
        
        stateLock.lock()
        cachedAudioObjectsByBundleID = newCacheBundleID
        cachedAudioObjectsByPID = newCachePID
        cachedDefaultOutputDeviceUID = defUID
        stateLock.unlock()
        
        // Urutkan: aplikasi yang sedang bersuara di atas, lalu urut abjad
        detectedProcesses.sort {
            if $0.isPlayingAudio != $1.isPlayingAudio {
                return $0.isPlayingAudio && !$1.isPlayingAudio
            }
            return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
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
}
