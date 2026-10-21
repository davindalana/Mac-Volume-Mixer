import Foundation
import CoreAudio

/// Model yang merepresentasikan perangkat audio output macOS (Speaker internal, AirPods, Headphone, dll)
public struct AudioDevice: Identifiable, Hashable, Sendable {
    /// ID perangkat CoreAudio
    public let id: AudioDeviceID
    
    /// UID unik string perangkat (misal: "BuiltInSpeakerDevice")
    public let uid: String
    
    /// Nama human-readable perangkat (misal: "MacBook Pro Speakers")
    public var name: String
    
    /// Menandakan apakah perangkat ini merupakan output default saat ini
    public var isDefault: Bool
    
    /// Level volume perangkat dari 0.0 sampai 1.0
    public var volume: Float
    
    /// Status mute perangkat
    public var isMuted: Bool
    
    // MARK: - Initializer
    public init(
        id: AudioDeviceID,
        uid: String,
        name: String,
        isDefault: Bool = false,
        volume: Float = 1.0,
        isMuted: Bool = false
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isDefault = isDefault
        self.volume = max(0.0, min(1.0, volume))
        self.isMuted = isMuted
    }
    
    /// Menghasilkan SF Symbol icon yang relevan berdasarkan nama perangkat
    public var systemIconName: String {
        let lower = name.lowercased()
        if lower.contains("airpod") {
            return "airpodspro"
        } else if lower.contains("headphone") || lower.contains("headset") {
            return "headphones"
        } else if lower.contains("display") || lower.contains("hdmi") || lower.contains("tv") {
            return "tv.fill"
        } else if lower.contains("bluetooth") {
            return "wave.3.right.circle.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }
}

// MARK: - Mock Data
#if DEBUG
extension AudioDevice {
    public static let mockDefault = AudioDevice(
        id: 110,
        uid: "BuiltInSpeakerDevice",
        name: "MacBook Pro Speakers",
        isDefault: true,
        volume: 0.75,
        isMuted: false
    )
    
    public static let mockList: [AudioDevice] = [
        mockDefault,
        AudioDevice(
            id: 115,
            uid: "AirPodsProDeviceUID",
            name: "AirPods Pro",
            isDefault: false,
            volume: 0.90,
            isMuted: false
        ),
        AudioDevice(
            id: 120,
            uid: "ExternalMonitorHDMI",
            name: "Dell 4K Display Audio",
            isDefault: false,
            volume: 0.50,
            isMuted: false
        )
    ]
}
#endif
