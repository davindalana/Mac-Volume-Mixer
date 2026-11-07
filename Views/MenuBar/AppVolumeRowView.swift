import SwiftUI
import AppKit

/// Baris kontrol volume individual per aplikasi sesuai tema Liquid Glass macOS Sonoma & Sequoia.
/// Layout: [App Icon] [App Name & Output Device Pill] [Spacer] [Mute Button] [CustomSlider] [Percentage] [Remove Button]
public struct AppVolumeRowView: View {
    public let process: AudioProcess
    public let availableDevices: [AudioDevice]
    public let onVolumeChange: (Float) -> Void
    public let onMuteToggle: () -> Void
    public let onOutputDeviceChange: ((AudioDevice?) -> Void)?
    public let onRemove: (() -> Void)?
    
    @State private var localVolume: Float
    @State private var isHovered: Bool = false
    @State private var isIconHovered: Bool = false
    @State private var isDeviceHovered: Bool = false
    @State private var isMuteHovered: Bool = false
    @State private var isRemoveHovered: Bool = false
    @State private var isShowingDevicePopover: Bool = false
    
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
    
    private var defaultDevice: AudioDevice? {
        availableDevices.first(where: { $0.isDefault })
    }
    
    private var currentDevice: AudioDevice? {
        if let uid = process.outputDeviceUID {
            return availableDevices.first(where: { $0.uid == uid })
        }
        return nil
    }
    
    private var audioIndicatorDot: some View {
        Circle()
            .fill(Color(red: 0.18, green: 0.88, blue: 0.38))
            .frame(width: 6.5, height: 6.5)
            .overlay(Circle().stroke(Color.black.opacity(0.85), lineWidth: 0.8))
            .shadow(color: Color.green.opacity(0.85), radius: 2.5)
            .offset(x: 1, y: 1)
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            // MARK: - 1. App Icon with Active Audio Indicator (Clickable to activate app)
            Button(action: {
                if let app = NSRunningApplication(processIdentifier: process.pid) {
                    app.activate()
                }
            }) {
                ZStack(alignment: .bottomTrailing) {
                    AppIconView(icon: process.icon, size: 26)
                        .padding(2)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isIconHovered ? Color.white.opacity(0.12) : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(isIconHovered ? Color.white.opacity(0.18) : Color.clear, lineWidth: 0.8)
                                )
                        )
                    
                    if process.isPlayingAudio {
                        audioIndicatorDot
                    }
                }
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandOnHover()
            .onHover { h in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isIconHovered = h
                }
            }
            
            // MARK: - 2. App Name & Modern Glass Output Device Pill
            VStack(alignment: .leading, spacing: 2.5) {
                Text(cleanAppName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(process.isMuted ? Color.secondary.opacity(0.6) : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                // Clickable Output Device Pill with Animated Popover
                if let onOutputDeviceChange = onOutputDeviceChange, !availableDevices.isEmpty {
                    Button(action: {
                        isShowingDevicePopover.toggle()
                    }) {
                        HStack(spacing: 3.5) {
                            Image(systemName: currentDevice?.systemIconName ?? (defaultDevice?.systemIconName ?? "speaker.wave.2.fill"))
                                .font(.system(size: 8))
                            
                            Text(currentDevice?.name ?? "Default Output")
                                .font(.system(size: 9.5, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            Image(systemName: "chevron.down")
                                .font(.system(size: 6.5, weight: .bold))
                                .opacity(0.7)
                        }
                        .foregroundColor(process.outputDeviceUID != nil ? Color.accentColor : (isDeviceHovered ? Color.primary : Color.primary.opacity(0.85)))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    process.outputDeviceUID != nil
                                        ? Color.accentColor.opacity(isDeviceHovered ? 0.30 : 0.20)
                                        : Color.white.opacity(isDeviceHovered ? 0.18 : 0.08)
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(
                                            process.outputDeviceUID != nil
                                                ? Color.accentColor.opacity(isDeviceHovered ? 0.60 : 0.45)
                                                : Color.white.opacity(isDeviceHovered ? 0.25 : 0.12),
                                            lineWidth: 0.8
                                        )
                                )
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointingHandOnHover()
                    .onHover { h in
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isDeviceHovered = h
                        }
                    }
                    .popover(isPresented: $isShowingDevicePopover, arrowEdge: .bottom) {
                        DevicePickerPopover(
                            appName: cleanAppName,
                            availableDevices: availableDevices,
                            currentDeviceUID: process.outputDeviceUID,
                            onSelect: { selectedDev in
                                onOutputDeviceChange(selectedDev)
                            },
                            onClose: {
                                isShowingDevicePopover = false
                            }
                        )
                    }
                }
            }
            .frame(width: 110, alignment: .leading)
            
            Spacer(minLength: 4)
            
            // MARK: - 3. Mute Button (Glass circle with pointer)
            Button(action: onMuteToggle) {
                Image(systemName: process.isMuted ? "speaker.slash.fill" : "speaker.wave.2")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(process.isMuted ? Color.red.opacity(0.9) : (isMuteHovered ? Color.primary : Color.secondary))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(
                                process.isMuted
                                    ? Color.red.opacity(isMuteHovered ? 0.30 : 0.18)
                                    : (isMuteHovered ? Color.white.opacity(0.14) : Color.clear)
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        process.isMuted
                                            ? Color.red.opacity(isMuteHovered ? 0.50 : 0.25)
                                            : (isMuteHovered ? Color.white.opacity(0.20) : Color.clear),
                                        lineWidth: 0.8
                                    )
                            )
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .pointingHandOnHover()
            .onHover { h in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isMuteHovered = h
                }
            }
            
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
                            .foregroundColor(isRemoveHovered ? Color.red.opacity(0.9) : Color.secondary.opacity(0.7))
                            .frame(width: 14, height: 14)
                            .background(
                                Circle()
                                    .fill(isRemoveHovered ? Color.white.opacity(0.12) : Color.clear)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .pointingHandOnHover()
                    .onHover { h in
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isRemoveHovered = h
                        }
                    }
                } else {
                    Color.clear
                        .frame(width: 14, height: 14)
                }
            }
            .frame(width: 14, height: 14)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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
                Button("Hapus dari Mixer", action: onRemove)
            }
            Button(process.isMuted ? "Bunyikan (Unmute)" : "Bisukan (Mute)", action: onMuteToggle)
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
            process: AudioProcess(pid: 101, appName: "Safari", volume: 1.0, isMuted: false, isPlayingAudio: false),
            onVolumeChange: { _ in },
            onMuteToggle: {}
        )
        AppVolumeRowView(
            process: AudioProcess(pid: 102, appName: "Music", volume: 0.90, isMuted: false, isPlayingAudio: true),
            onVolumeChange: { _ in },
            onMuteToggle: {}
        )
    }
    .padding()
    .frame(width: 380)
    .background(Color(red: 0.13, green: 0.13, blue: 0.14))
}
