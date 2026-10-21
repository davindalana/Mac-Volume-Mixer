import SwiftUI

/// Baris kontrol volume individual per aplikasi.
/// Berisi icon aplikasi (24x24), nama aplikasi (truncated), slider interaktif, feedback nilai persentase, dan tombol mute.
public struct AppVolumeRowView: View {
    public let process: AudioProcess
    public let onVolumeChange: (Float) -> Void
    public let onMuteToggle: () -> Void
    
    @State private var localVolume: Float
    @State private var isHovered: Bool = false
    
    public init(
        process: AudioProcess,
        onVolumeChange: @escaping (Float) -> Void,
        onMuteToggle: @escaping () -> Void
    ) {
        self.process = process
        self.onVolumeChange = onVolumeChange
        self.onMuteToggle = onMuteToggle
        self._localVolume = State(initialValue: process.volume)
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            // MARK: - App Icon & Audio Indicator
            ZStack(alignment: .bottomTrailing) {
                AppIconView(icon: process.icon, size: 24)
                
                // Indikator hijau kecil jika aplikasi sedang aktif memutar audio
                if process.isPlayingAudio {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(Color.black, lineWidth: 1))
                        .offset(x: 2, y: 2)
                }
            }
            
            // MARK: - App Name
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(process.appName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(process.isMuted ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help("\(process.appName) (PID: \(process.pid))")
                    
                    if process.isPlayingAudio {
                        Image(systemName: "waveform")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                            .symbolEffect(.variableColor.iterative, isActive: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 85, alignment: .leading)
            
            // MARK: - Volume Slider
            CustomSlider(
                value: Binding(
                    get: { localVolume },
                    set: { newVal in
                        localVolume = newVal
                        onVolumeChange(newVal)
                    }
                ),
                isMuted: process.isMuted,
                accentColors: [Color.blue, Color.cyan]
            )
            .frame(maxWidth: .infinity)
            
            // MARK: - Percentage Feedback
            Text(process.isMuted ? "Muted" : "\(Int(round(localVolume * 100)))%")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(process.isMuted ? .secondary : .secondary)
                .frame(width: 42, alignment: .trailing)
            
            // MARK: - Mute Toggle Button
            Button(action: onMuteToggle) {
                Image(systemName: process.isMuted ? "speaker.slash.fill" : (localVolume > 0.5 ? "speaker.wave.2.fill" : "speaker.wave.1.fill"))
                    .font(.system(size: 12))
                    .foregroundColor(process.isMuted ? .red : (isHovered ? .primary : .secondary))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(process.isMuted ? "Unmute \(process.appName)" : "Mute \(process.appName)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
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
            process: AudioProcess(pid: 101, appName: "Spotify", volume: 0.8, isMuted: false, isPlayingAudio: true),
            onVolumeChange: { _ in },
            onMuteToggle: {}
        )
        AppVolumeRowView(
            process: AudioProcess(pid: 102, appName: "Discord Communication App Very Long Name", volume: 0.35, isMuted: true, isPlayingAudio: false),
            onVolumeChange: { _ in },
            onMuteToggle: {}
        )
    }
    .padding()
    .frame(width: 320)
}
