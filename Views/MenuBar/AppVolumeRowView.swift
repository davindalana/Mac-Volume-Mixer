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
            
            // MARK: - 2. App Name & Output Device Indicator
            VStack(alignment: .leading, spacing: 1) {
                Text(cleanAppName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(process.isMuted ? Color(white: 0.5) : Color(white: 0.95))
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
                                .font(.system(size: 8))
                            Text(currentDevice?.name ?? "Default Output")
                                .font(.system(size: 9.5))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7))
                        }
                        .foregroundColor(process.outputDeviceUID != nil ? Color.orange : Color(white: 0.5))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            
            Spacer(minLength: 6)
            
            // MARK: - 3. Mute Button (Speaker with Slash)
            Button(action: onMuteToggle) {
                Image(systemName: process.isMuted ? "speaker.slash.fill" : "speaker.slash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(process.isMuted ? Color(red: 1.0, green: 0.35, blue: 0.35) : (isHovered ? Color.white : Color(white: 0.6)))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(process.isMuted ? "Unmute \(cleanAppName)" : "Mute \(cleanAppName)")
            
            // MARK: - 4. Volume Slider (Dark Track, Orange Progress, White Knob, 0% - 200%)
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
                accentColor: Color(red: 1.0, green: 0.584, blue: 0.0)
            )
            .frame(width: 120)
            
            // MARK: - 5. Percentage Label (e.g. 100%, 150%, 200%)
            Text("\(Int(round(localVolume * 100)))%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(process.isMuted ? Color(white: 0.45) : (localVolume > 1.0 ? Color(red: 1.0, green: 0.75, blue: 0.2) : Color(white: 0.75)))
                .frame(width: 36, alignment: .trailing)
            
            // MARK: - 6. Optional Remove Button (on hover)
            if let onRemove = onRemove, isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color(white: 0.5))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help("Remove from Mixer")
            } else {
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
