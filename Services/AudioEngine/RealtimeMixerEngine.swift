import Foundation
import CoreAudio
import AudioToolbox
import os.log

/// Session DSP aktif per aplikasi / bundleID
private final class AppTapSession {
    let key: String
    var gain: Float32
    var tapID: AudioObjectID = 0
    var aggDeviceID: AudioDeviceID = 0
    var ioProcID: AudioDeviceIOProcID? = nil
    var opaqueSelf: UnsafeMutableRawPointer? = nil
    
    init(key: String, gain: Float32) {
        self.key = key
        self.gain = gain
    }
}

// IOProc C-callback untuk DSP attenuation real-time
private func mixerEngineIOProc(
    inDevice: AudioObjectID,
    inNow: UnsafePointer<AudioTimeStamp>,
    inInputData: UnsafePointer<AudioBufferList>,
    inInputTime: UnsafePointer<AudioTimeStamp>,
    outOutputData: UnsafeMutablePointer<AudioBufferList>,
    inOutputTime: UnsafePointer<AudioTimeStamp>,
    inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let ptr = inClientData else { return noErr }
    let session = Unmanaged<AppTapSession>.fromOpaque(ptr).takeUnretainedValue()
    let g = session.gain
    
    let inBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
    let outBuffers = UnsafeMutableAudioBufferListPointer(outOutputData)
    
    let inCount = inBuffers.count
    let outCount = outBuffers.count
    let commonCount = min(inCount, outCount)
    
    for i in 0..<commonCount {
        let inBuf = inBuffers[i]
        let outBuf = outBuffers[i]
        guard let inData = inBuf.mData?.assumingMemoryBound(to: Float32.self),
              let outData = outBuf.mData?.assumingMemoryBound(to: Float32.self) else { continue }
        
        let byteSize = min(inBuf.mDataByteSize, outBuf.mDataByteSize)
        let frameCount = Int(byteSize) / MemoryLayout<Float32>.size
        for j in 0..<frameCount {
            let sample = inData[j] * g
            // Soft-limiting clamping agar tidak terjadi digital clipping saat boost hingga 200%
            outData[j] = max(-1.0, min(1.0, sample))
        }
    }
    
    if outCount > inCount {
        for i in inCount..<outCount {
            let outBuf = outBuffers[i]
            if let outData = outBuf.mData {
                memset(outData, 0, Int(outBuf.mDataByteSize))
            }
        }
    }
    
    return noErr
}

/// Engine mixing audio DSP real-time menggunakan AudioHardwareCreateProcessTap,
/// CoreAudio Aggregate Device, dan callback AudioDeviceIOProc.
/// Mengatur volume floating-point PCM secara independen per aplikasi / bundleID.
public final class RealtimeMixerEngine: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.macvolumemixer.app", category: "RealtimeMixerEngine")
    private let lock = NSLock()
    private var sessions: [String: AppTapSession] = [:]
    
    public init() {}
    
    deinit {
        stop()
    }
    
    /// Mengatur volume aplikasi secara real-time via hardware process tap dan DSP mixing (0% - 200%)
    public func setVolume(
        for key: String,
        targetObjects: [AudioObjectID],
        defaultDeviceUID: String,
        volume: Float,
        isMuted: Bool
    ) {
        guard #available(macOS 14.2, *) else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        let effectiveGain = isMuted ? 0.0 : max(0.0, min(2.0, Float32(volume)))
        
        // 1. Jika volume tepat 1.0 (100% dan tidak dimute), tidak perlu DSP intercept - bypass native bit-perfect
        if abs(effectiveGain - 1.0) < 0.001 {
            if let session = sessions.removeValue(forKey: key) {
                tearDownSession(session)
                logger.info("Session DSP untuk \(key) dihentikan (kembali ke 100% native bypass)")
            }
            return
        }
        
        // 2. Jika session sudah ada, cukup update gain secara atomik tanpa restart device!
        if let session = sessions[key] {
            session.gain = effectiveGain
            logger.debug("Gain session \(key) diperbarui ke \(effectiveGain)")
            return
        }
        
        // 3. Jika belum ada session dan targetObjects tersedia, buat session baru
        guard !targetObjects.isEmpty, !defaultDeviceUID.isEmpty else { return }
        
        createSession(
            key: key,
            targetObjects: targetObjects,
            defaultDeviceUID: defaultDeviceUID,
            initialGain: effectiveGain
        )
    }
    
    private func createSession(
        key: String,
        targetObjects: [AudioObjectID],
        defaultDeviceUID: String,
        initialGain: Float32
    ) {
        guard #available(macOS 14.2, *) else { return }
        
        let tapDesc = CATapDescription(stereoMixdownOfProcesses: targetObjects)
        tapDesc.name = "MixerTap_\(key)"
        tapDesc.isPrivate = true
        tapDesc.muteBehavior = .muted // Mute direct hardware output
        
        var tapID: AudioObjectID = 0
        let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        guard tapStatus == noErr, tapID != 0 else {
            logger.error("Gagal membuat process tap untuk \(key): status \(tapStatus)")
            return
        }
        
        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfTapUID: Unmanaged<CFString>? = nil
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let sUID = AudioObjectGetPropertyData(tapID, &uidAddr, 0, nil, &uidSize, &cfTapUID)
        guard sUID == noErr, let tapUID = cfTapUID?.takeRetainedValue() as String? else {
            _ = AudioHardwareDestroyProcessTap(tapID)
            return
        }
        
        let aggUID = "com.macvolumemixer.dsp." + UUID().uuidString
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Mixer_\(key)",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceMainSubDeviceKey: defaultDeviceUID,
            kAudioAggregateDeviceClockDeviceKey: defaultDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: defaultDeviceUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID]
            ]
        ]
        
        var aggDeviceID: AudioDeviceID = 0
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggDeviceID)
        guard aggStatus == noErr, aggDeviceID != 0 else {
            logger.error("Gagal membuat aggregate device untuk \(key): status \(aggStatus)")
            _ = AudioHardwareDestroyProcessTap(tapID)
            return
        }
        
        let session = AppTapSession(key: key, gain: initialGain)
        session.tapID = tapID
        session.aggDeviceID = aggDeviceID
        
        let opaque = Unmanaged.passRetained(session).toOpaque()
        session.opaqueSelf = opaque
        
        var procID: AudioDeviceIOProcID? = nil
        let procStatus = AudioDeviceCreateIOProcID(aggDeviceID, mixerEngineIOProc, opaque, &procID)
        guard procStatus == noErr, let pID = procID else {
            logger.error("Gagal membuat IOProc untuk \(key)")
            Unmanaged<AppTapSession>.fromOpaque(opaque).release()
            _ = AudioHardwareDestroyAggregateDevice(aggDeviceID)
            _ = AudioHardwareDestroyProcessTap(tapID)
            return
        }
        
        session.ioProcID = pID
        let startStatus = AudioDeviceStart(aggDeviceID, pID)
        guard startStatus == noErr else {
            logger.error("Gagal memulai AudioDeviceStart untuk \(key)")
            tearDownSession(session)
            return
        }
        
        sessions[key] = session
        logger.info("DSP Audio Session aktif untuk \(key), gain=\(initialGain), targetObjects=\(targetObjects)")
    }
    
    private func tearDownSession(_ session: AppTapSession) {
        guard #available(macOS 14.2, *) else { return }
        if let pID = session.ioProcID, session.aggDeviceID != 0 {
            _ = AudioDeviceStop(session.aggDeviceID, pID)
            _ = AudioDeviceDestroyIOProcID(session.aggDeviceID, pID)
        }
        if session.aggDeviceID != 0 {
            _ = AudioHardwareDestroyAggregateDevice(session.aggDeviceID)
        }
        if session.tapID != 0 {
            _ = AudioHardwareDestroyProcessTap(session.tapID)
        }
        if let opaque = session.opaqueSelf {
            Unmanaged<AppTapSession>.fromOpaque(opaque).release()
            session.opaqueSelf = nil
        }
    }
    
    public func stop() {
        guard #available(macOS 14.2, *) else { return }
        lock.lock()
        defer { lock.unlock() }
        for (_, session) in sessions {
            tearDownSession(session)
        }
        sessions.removeAll()
    }
}
