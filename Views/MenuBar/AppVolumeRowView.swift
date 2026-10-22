import SwiftUI

/// Baris kontrol volume individual per aplikasi sesuai screenshot (SoundSource style).
/// Layout: [App Icon 22x22] [App Name] [Spacer] [Mute Button (Speaker Slash)] [CustomSlider (Orange / White)]
public struct AppVolumeRowView: View {
    public let process: AudioProcess
    public let onVolumeChange: (Float) -> Void
    public let onMuteToggle: () -> Void
    public let onRemove: (() -> Void)?
    
    @State private var localVolume: Float
    @State private var isHovered: Bool = false
    
    public init(
        process: AudioProcess,
        onVolumeChange: @escaping (Float) -> Void,
        onMuteToggle: @escaping () -> Void,
        onRemove: (() -> Void)? = nil
    ) {
        self.process = process
        self.onVolumeChange = onVolumeChange
        self.onMuteToggle = onMuteToggle
        self.onRemove = onRemove
        self._localVolume = State(initialValue: process.volume)
    }
    
    private var cleanAppName: String {
        process.appName
            .replacingOccurrences(of: "\u{200E}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            // MARK: - 1. App Icon
            ZStack(alignment: .bottomTrailing) {
                AppIconView(icon: process.icon, size: 22)
                
                if process.isPlayingAudio {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.85, blue: 0.35))
                        .frame(width: 5, height: 5)
                        .overlay(Circle().stroke(Color.black.opacity(0.8), lineWidth: 0.7))
                        .offset(x: 1, y: 1)
                }
            }
            .frame(width: 22, height: 22)
            
            // MARK: - 2. App Name
            Text(cleanAppName)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(process.isMuted ? Color(white: 0.5) : Color(white: 0.95))
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer(minLength: 8)
            
            // MARK: - 3. Mute Button (Speaker with Slash)
            Button(action: onMuteToggle) {
                Image(systemName: process.isMuted ? "speaker.slash.fill" : "speaker.slash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(process.isMuted ? Color(red: 1.0, green: 0.35, blue: 0.35) : (isHovered ? Color.white : Color(white: 0.6)))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(process.isMuted ? "Unmute \(cleanAppName)" : "Mute \(cleanAppName)")
            
            // MARK: - 4. Volume Slider (Dark Track, Orange Progress, White Knob)
            CustomSlider(
                value: Binding(
                    get: { localVolume },
                    set: { newVal in
                        localVolume = newVal
                        onVolumeChange(newVal)
                    }
                ),
                isMuted: process.isMuted,
                accentColor: Color(red: 1.0, green: 0.584, blue: 0.0)
            )
            .frame(width: 140)
            
            // MARK: - 5. Optional Remove Button (on hover)
            if let onRemove = onRemove, isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color(white: 0.5))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help("Remove from Mixer")
            } else if onRemove != nil {
                Spacer().frame(width: 14)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3.5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .contextMenu {
            if let onRemove = onRemove {
                Button("Remove from Mixer", action: onRemove)
            }
            Button(process.isMuted ? "Unmute" : "Mute", action: onMuteToggle)
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onChange(of: process.volume) { _, newVol in
            localVolume = newVol
        }
    }
}

#Preview {
    VStack(spacing: 4) {
        AppVolumeRowView(
            process: AudioProcess(pid: 101, appName: "Finder", volume: 1.0, isMuted: false, isPlayingAudio: false),
            onVolumeChange: { _ in },
            onMuteToggle: {}
        )
        AppVolumeRowView(
            process: AudioProcess(pid: 102, appName: "Music", volume: 0.90, isMuted: false, isPlayingAudio: true),
            onVolumeChange: { _ in },
            onMuteToggle: {}
        )
        AppVolumeRowView(
            process: AudioProcess(pid: 103, appName: "Safari", volume: 0.45, isMuted: false, isPlayingAudio: true),
            onVolumeChange: { _ in },
            onMuteToggle: {}
        )
        AppVolumeRowView(
            process: AudioProcess(pid: 104, appName: "WhatsApp", volume: 0.50, isMuted: false, isPlayingAudio: false),
            onVolumeChange: { _ in },
            onMuteToggle: {},
            onRemove: {}
        )
    }
    .padding()
    .frame(width: 320)
    .background(Color(red: 0.13, green: 0.13, blue: 0.14))
}
