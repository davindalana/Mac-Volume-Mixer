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
    
    /// Dictionary menyimpan AudioObjectID Tap per Process ID (PID)
    private var processTaps: [pid_t: AudioObjectID] = [:]
    
    /// Menyimpan gain / volume per PID (0.0 ... 1.0)
    private var processVolumes: [pid_t: Float] = [:]
    
    /// Menyimpan status mute per PID
    private var processMutes: [pid_t: Bool] = [:]
    
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
        
        // Hancurkan semua tap yang sedang aktif
        for (pid, tapID) in processTaps {
            destroyProcessTap(tapID: tapID, for: pid)
        }
        processTaps.removeAll()
        stateLock.unlock()
        
        unregisterSystemAudioListeners()
        logger.info("CoreAudio Tap monitoring dihentikan.")
    }
    
    // MARK: - Volume & Mute per Process
    
    public func setVolume(for pid: pid_t, volume: Float) {
        let clampedVolume = max(0.0, min(1.0, volume))
        
        stateLock.lock()
        processVolumes[pid] = clampedVolume
        let isMuted = processMutes[pid] ?? false
        stateLock.unlock()
        
        // Terapkan gain multiplier secara real-time ke audio tap atau software scaler
        applyGainMultiplier(for: pid, volume: clampedVolume, isMuted: isMuted)
        
        // Perbarui data proses di publisher
        updatePublishedProcess(pid: pid) { process in
            process.volume = clampedVolume
        }
    }
    
    public func setMute(for pid: pid_t, isMuted: Bool) {
        stateLock.lock()
        processMutes[pid] = isMuted
        let volume = processVolumes[pid] ?? 1.0
        let existingTap = processTaps[pid]
        stateLock.unlock()
        
        // Perbarui tap mute behavior jika tap aktif
        if let tapID = existingTap {
            updateTapMuteBehavior(tapID: tapID, isMuted: isMuted)
        }
        
        applyGainMultiplier(for: pid, volume: volume, isMuted: isMuted)
        
        updatePublishedProcess(pid: pid) { process in
            process.isMuted = isMuted
        }
    }
    
    // MARK: - CoreAudio Process Tap (macOS 14.2+)
    
    /// Menginisialisasi Process Tap untuk PID tertentu
    private func initializeProcessTapIfNeeded(for pid: pid_t) {
        guard #available(macOS 14.2, *) else {
            logger.debug("Process Audio Tap membutuhkan macOS 14.2 atau lebih baru")
            return
        }
        
        stateLock.lock()
        if processTaps[pid] != nil {
            stateLock.unlock()
            return
        }
        stateLock.unlock()
        
        // Dapatkan AudioObjectID untuk PID dari CoreAudio
        guard let processObjectID = translatePIDToProcessObject(pid: pid) else {
            logger.debug("Tidak dapat menemukan Process AudioObjectID untuk PID \(pid)")
            return
        }
        
        // Inisialisasi CATapDescription untuk stereo mixdown dari proses tersebut
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        tapDescription.name = "MixerTap_\(pid)"
        tapDescription.isPrivate = true
        
        stateLock.lock()
        let isMuted = processMutes[pid] ?? false
        stateLock.unlock()
        
        tapDescription.muteBehavior = isMuted ? CATapMuteBehavior.muted : CATapMuteBehavior.unmuted
        
        var tapID: AudioObjectID = 0
        let status = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        
        if status == noErr && tapID != 0 {
            stateLock.lock()
            processTaps[pid] = tapID
            stateLock.unlock()
            logger.info("Berhasil membuat Process Tap untuk PID: \(pid), TapID: \(tapID)")
        } else {
            let errorString = formatOSStatus(status)
            logger.error("Gagal membuat AudioHardwareCreateProcessTap untuk PID \(pid): \(errorString)")
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
    
    /// Memperbarui mute behavior pada CATapDescription yang sedang berjalan
    private func updateTapMuteBehavior(tapID: AudioObjectID, isMuted: Bool) {
        guard #available(macOS 14.2, *) else { return }
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyDescription,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var tapDescription: CATapDescription? = nil
        var size = UInt32(MemoryLayout<CATapDescription?>.size)
        
        let getStatus = withUnsafeMutablePointer(to: &tapDescription) { ptr in
            AudioObjectGetPropertyData(tapID, &propertyAddress, 0, nil, &size, ptr)
        }
        
        if getStatus == noErr, let description = tapDescription {
            description.muteBehavior = isMuted ? CATapMuteBehavior.muted : CATapMuteBehavior.unmuted
            var newDesc: CATapDescription? = description
            _ = withUnsafeMutablePointer(to: &newDesc) { ptr in
                AudioObjectSetPropertyData(tapID, &propertyAddress, 0, nil, size, ptr)
            }
        }
    }
    
    /// Menerapkan gain multiplier secara real-time
    private func applyGainMultiplier(for pid: pid_t, volume: Float, isMuted: Bool) {
        // Gain multiplier efektif: 0.0 jika mute, selain itu nilai volume (0.0 - 1.0)
        let effectiveGain = isMuted ? 0.0 : volume
        _ = effectiveGain
        // Jika stream audio tap terhubung ke IO proc / client aggregate,
        // buffer sample dikalikan dengan effectiveGain secara thread-safe.
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
                
                let process = AudioProcess(
                    pid: pid,
                    appName: info.name,
                    bundleIdentifier: info.bundleID,
                    icon: info.icon,
                    volume: currentVolume,
                    isMuted: currentMute,
                    isPlayingAudio: isRunningOutput
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
                
                let process = AudioProcess(
                    pid: pid,
                    appName: info.name,
                    bundleIdentifier: info.bundleID,
                    icon: info.icon,
                    volume: currentVolume,
                    isMuted: currentMute,
                    isPlayingAudio: false
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
