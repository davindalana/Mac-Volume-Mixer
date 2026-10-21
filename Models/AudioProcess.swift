import Foundation
import AppKit

/// Model yang merepresentasikan proses aplikasi yang berinteraksi dengan audio stream.
public struct AudioProcess: Identifiable, Hashable, @unchecked Sendable {
    /// Identifier unik untuk SwiftUI list (menggunakan PID proses)
    public var id: pid_t { pid }
    
    /// Process Identifier (PID) sistem macOS
    public let pid: pid_t
    
    /// Nama aplikasi yang tampil di antarmuka pengguna
    public var appName: String
    
    /// Bundle Identifier aplikasi (misal: "com.spotify.client")
    public var bundleIdentifier: String?
    
    /// Icon aplikasi (diambil via NSWorkspace / NSRunningApplication)
    public var icon: NSImage?
    
    /// Level volume dari 0.0 (hening) hingga 1.0 (maksimal)
    public var volume: Float
    
    /// Status mute aplikasi
    public var isMuted: Bool
    
    /// Indikator apakah aplikasi saat ini sedang aktif memancarkan sinyal audio
    public var isPlayingAudio: Bool
    
    // MARK: - Initializer
    public init(
        pid: pid_t,
        appName: String,
        bundleIdentifier: String? = nil,
        icon: NSImage? = nil,
        volume: Float = 1.0,
        isMuted: Bool = false,
        isPlayingAudio: Bool = false
    ) {
        self.pid = pid
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.icon = icon
        self.volume = max(0.0, min(1.0, volume))
        self.isMuted = isMuted
        self.isPlayingAudio = isPlayingAudio
    }
    
    // MARK: - Computed Properties
    /// Nilai volume efektif (0.0 jika di-mute, selain itu nilai volume aktual)
    public var effectiveVolume: Float {
        isMuted ? 0.0 : volume
    }
    
    /// Nilai persentase volume dalam bilangan bulat (0% - 100%)
    public var volumePercentage: Int {
        Int(round(volume * 100))
    }
    
    /// Teks format persentase volume (misal: "75%")
    public var volumeString: String {
        "\(volumePercentage)%"
    }
    
    // MARK: - Hashable & Equatable
    public static func == (lhs: AudioProcess, rhs: AudioProcess) -> Bool {
        return lhs.pid == rhs.pid &&
               lhs.appName == rhs.appName &&
               lhs.bundleIdentifier == rhs.bundleIdentifier &&
               lhs.volume == rhs.volume &&
               lhs.isMuted == rhs.isMuted &&
               lhs.isPlayingAudio == rhs.isPlayingAudio
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(appName)
        hasher.combine(bundleIdentifier)
        hasher.combine(volume)
        hasher.combine(isMuted)
        hasher.combine(isPlayingAudio)
    }
}

// MARK: - Mock Data for Previews
#if DEBUG
extension AudioProcess {
    public static let mockList: [AudioProcess] = [
        AudioProcess(
            pid: 1001,
            appName: "Spotify",
            bundleIdentifier: "com.spotify.client",
            icon: NSWorkspace.shared.icon(forFile: "/Applications/Spotify.app"),
            volume: 0.85,
            isMuted: false,
            isPlayingAudio: true
        ),
        AudioProcess(
            pid: 1002,
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            icon: NSWorkspace.shared.icon(forFile: "/Applications/Safari.app"),
            volume: 0.60,
            isMuted: false,
            isPlayingAudio: true
        ),
        AudioProcess(
            pid: 1003,
            appName: "Discord",
            bundleIdentifier: "com.hnc.Discord",
            icon: NSWorkspace.shared.icon(forFile: "/Applications/Discord.app"),
            volume: 0.40,
            isMuted: true,
            isPlayingAudio: false
        ),
        AudioProcess(
            pid: 1004,
            appName: "Music",
            bundleIdentifier: "com.apple.Music",
            icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Music.app"),
            volume: 1.0,
            isMuted: false,
            isPlayingAudio: false
        )
    ]
}
#endif
