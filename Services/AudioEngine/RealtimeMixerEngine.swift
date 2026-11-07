import Foundation
import CoreAudio
import AudioToolbox
import CoreGraphics
import Accelerate
import os.log

/// Session DSP aktif per aplikasi / bundleID
private final class AppTapSession {
    let key: String
    var gain: Float32
    var targetObjects: Set<AudioObjectID>
    var deviceUID: String
    var tapID: AudioObjectID = 0
    var aggDeviceID: AudioDeviceID = 0
    var ioProcID: AudioDeviceIOProcID? = nil
    var opaqueSelf: UnsafeMutableRawPointer? = nil
    
    init(key: String, gain: Float32, targetObjects: Set<AudioObjectID>, deviceUID: String) {
        self.key = key
        self.gain = gain
        self.targetObjects = targetObjects
        self.deviceUID = deviceUID
    }
}

// IOProc C-callback untuk DSP attenuation & amplification real-time berbasis hardware SIMD / vDSP (Accelerate)
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
    var g = session.gain
    
    let inBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
    let outBuffers = UnsafeMutableAudioBufferListPointer(outOutputData)
    
    let inCount = inBuffers.count
    let outCount = outBuffers.count
    let commonCount = min(inCount, outCount)
    
    var minLimit: Float32 = -1.0
    var maxLimit: Float32 = 1.0
    
    for i in 0..<commonCount {
        let inBuf = inBuffers[i]
        let outBuf = outBuffers[i]
        guard let inData = inBuf.mData?.assumingMemoryBound(to: Float32.self),
              let outData = outBuf.mData?.assumingMemoryBound(to: Float32.self) else { continue }
        
        let byteSize = min(inBuf.mDataByteSize, outBuf.mDataByteSize)
        let frameCount = vDSP_Length(Int(byteSize) / MemoryLayout<Float32>.size)
        
        if frameCount > 0 {
            // Operasi perkalian vektor termultithread SIMD (hardware acceleration)
            vDSP_vsmul(inData, 1, &g, outData, 1, frameCount)
            
            // Soft-clamping vectorized hardware limit (-1.0 ... 1.0) untuk mencegah distorsi
            if g > 1.0 {
                vDSP_vclip(outData, 1, &minLimit, &maxLimit, outData, 1, frameCount)
            }
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
/// Mengatur volume floating-point PCM secara independen per aplikasi / bundleID (0% - 200%).
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
        let targetSet = Set(targetObjects)
        
        // 1. Jika session sudah ada
        if let session = sessions[key] {
            // Periksa apakah target objects atau device output berubah
            let deviceChanged = session.deviceUID != defaultDeviceUID
            if (!targetObjects.isEmpty && session.targetObjects != targetSet) || deviceChanged {
                logger.info("Target objects atau target device untuk \(key) berubah (deviceChanged: \(deviceChanged)). Memperbarui audio tap session...")
                tearDownSession(session)
                sessions.removeValue(forKey: key)
                createSession(
                    key: key,
                    targetObjects: targetObjects,
                    defaultDeviceUID: defaultDeviceUID,
                    initialGain: effectiveGain
                )
                return
            }
            
            // Cukup update gain secara atomik (0ms latency, zero glitch)
            session.gain = effectiveGain
            return
        }
        
        // 2. Jika belum ada session dan volume default 1.0 (serta tidak dimute) dan tidak di-route ke device kustom, biarkan native pass-through
        // Namun jika defaultDeviceUID berbeda atau caller meminta session aktif, buat session
        if abs(effectiveGain - 1.0) < 0.001 && !isMuted {
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
        
        let hasCapture = CGPreflightScreenCaptureAccess()
        // Kritis: Hanya set .muted jika Screen & Audio Recording permission aktif.
        // Jika belum aktif, gunakan .unmuted agar suara aplikasi tidak hilang.
        tapDesc.muteBehavior = hasCapture ? .muted : .unmuted
        if !hasCapture {
            logger.warning("ScreenCapture access belum aktif untuk \(key). Menggunakan .unmuted untuk keamanan audio.")
        }
        
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
        
        let session = AppTapSession(key: key, gain: initialGain, targetObjects: Set(targetObjects), deviceUID: defaultDeviceUID)
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
        logger.info("DSP Audio Session aktif untuk \(key), gain=\(initialGain), targets=\(targetObjects)")
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
