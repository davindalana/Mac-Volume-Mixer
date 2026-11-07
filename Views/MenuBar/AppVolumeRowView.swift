import SwiftUI

/// Baris kontrol volume individual per aplikasi sesuai screenshot (SoundSource style).
/// Layout: [App Icon 22x22] [App Name] [Output Device Menu] [Spacer] [Mute Button] [CustomSlider] [Percentage] [Remove Button]
public struct AppVolumeRowView: View {
    public let process: AudioProcess
    public let availableDevices: [AudioDevice]
    public let onVolumeChange: (Float) -> Void
    public let onMuteToggle: () -> Void
    public let onOutputDeviceChange: ((AudioDevice?) -> Void)?
    public let onRemove: (() -> Void)?
    
    @State private var localVolume: Float
    @State private var isHovered: Bool = false
    
    public init(
        process: AudioProcess,
        availableDevices: [AudioDevice] = [],
        onVolumeChange: @escaping (Float) -> Void,
        onMuteToggle: @escaping () -> Void,
        onOutputDeviceChange: ((AudioDevice?) -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) {
        self.process = process
        self.availableDevices = availableDevices
        self.onVolumeChange = onVolumeChange
        self.onMuteToggle = onMuteToggle
        self.onOutputDeviceChange = onOutputDeviceChange
        self.onRemove = onRemove
        self._localVolume = State(initialValue: process.volume)
    }
    
    private var cleanAppName: String {
        process.appName
            .replacingOccurrences(of: "\u{200E}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var currentDevice: AudioDevice? {
        if let uid = process.outputDeviceUID {
            return availableDevices.first(where: { $0.uid == uid })
        }
        return nil
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            // MARK: - 1. App Icon with Active Audio Indicator
            ZStack(alignment: .bottomTrailing) {
                AppIconView(icon: process.icon, size: 24)
                
                if process.isPlayingAudio {
                    Circle()
                        .fill(Color(red: 0.18, green: 0.85, blue: 0.38))
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(Color.black.opacity(0.85), lineWidth: 0.8))
                        .shadow(color: Color.green.opacity(0.8), radius: 2.5)
                        .offset(x: 1, y: 1)
                }
            }
            .frame(width: 24, height: 24)
            
            // MARK: - 2. App Name & Output Device Indicator
            VStack(alignment: .leading, spacing: 2) {
                Text(cleanAppName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(process.isMuted ? Color.secondary.opacity(0.6) : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                // Output device picker / indicator
                if let onOutputDeviceChange = onOutputDeviceChange, !availableDevices.isEmpty {
                    Menu {
                        Button(action: {
                            onOutputDeviceChange(nil)
                        }) {
                            HStack {
                                Text("System Default Output")
                                if process.outputDeviceUID == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        Divider()
                        
                        ForEach(availableDevices) { device in
                            Button(action: {
                                onOutputDeviceChange(device)
                            }) {
                                HStack {
                                    Text(device.name)
                                    if device.uid == process.outputDeviceUID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: currentDevice?.systemIconName ?? "speaker.wave.2")
                                .font(.system(size: 7.5))
                            Text(currentDevice?.name ?? "Default Output")
                                .font(.system(size: 9, weight: .regular))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 5.5, weight: .bold))
                                .opacity(0.5)
                        }
                        .foregroundColor(process.outputDeviceUID != nil ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(process.outputDeviceUID != nil ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.06))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(process.outputDeviceUID != nil ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.10), lineWidth: 0.6)
                                )
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }
            }
            .frame(width: 108, alignment: .leading)
            
            Spacer(minLength: 4)
            
            // MARK: - 3. Mute Button (Speaker with Slash)
            Button(action: onMuteToggle) {
                Image(systemName: process.isMuted ? "speaker.slash.fill" : "speaker.wave.2")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(process.isMuted ? Color.red.opacity(0.9) : (isHovered ? Color.primary : Color.secondary))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(process.isMuted ? Color.red.opacity(0.18) : (isHovered ? Color.white.opacity(0.08) : Color.clear))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(process.isMuted ? "Unmute \(cleanAppName)" : "Mute \(cleanAppName)")
            
            // MARK: - 4. Volume Slider (Modern macOS Accent, 0% - 200%)
            CustomSlider(
                value: Binding(
                    get: { localVolume },
                    set: { newVal in
                        localVolume = newVal
                        onVolumeChange(newVal)
                    }
                ),
                maxValue: 2.0,
                baselineValue: 1.0,
                isMuted: process.isMuted,
                accentColor: Color.accentColor
            )
            .frame(width: 100, height: 18)
            
            // MARK: - 5. Percentage Label (e.g. 100%, 150%, 200%)
            Text("\(Int(round(localVolume * 100)))%")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundColor(process.isMuted ? Color.secondary.opacity(0.5) : (localVolume > 1.0 ? Color.orange : Color.secondary))
                .frame(width: 34, alignment: .trailing)
            
            // MARK: - 6. Optional Remove Button (14pt)
            Group {
                if let onRemove = onRemove, isHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color.secondary.opacity(0.7))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from Mixer")
                } else {
                    Color.clear
                        .frame(width: 14, height: 14)
                }
            }
            .frame(width: 14, height: 14)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.07) : Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isHovered ? Color.white.opacity(0.14) : Color.white.opacity(0.05), lineWidth: 0.6)
                )
        )
        .contextMenu {
            if let onRemove = onRemove {
                Button("Remove from Mixer", action: onRemove)
            }
            Button(process.isMuted ? "Unmute" : "Mute", action: onMuteToggle)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
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
