import SwiftUI
import AppKit

/// Baris kontrol volume individual per aplikasi sesuai tema Liquid Glass macOS Sonoma & Sequoia.
/// Layout kolom konsisten: [Icon 26x26] [Nama & Output Pill 106] [Spacer] [Mute 20x20] [Slider 105x18] [% 34] [Hapus 14]
public struct AppVolumeRowView: View {
    public let process: AudioProcess
    public let availableDevices: [AudioDevice]
    public let onVolumeChange: (Float) -> Void
    public let onMuteToggle: () -> Void
    public let onOutputDeviceChange: ((AudioDevice?) -> Void)?
    public let onRemove: (() -> Void)?
    
    @State private var localVolume: Float
    @State private var isHovered: Bool = false
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
            .fill(Color(red: 0.20, green: 0.88, blue: 0.40))
            .frame(width: 7, height: 7)
            .overlay(Circle().stroke(Color.black.opacity(0.8), lineWidth: 1.0))
            .shadow(color: Color.green.opacity(0.7), radius: 2)
    }
    
    public var body: some View {
        HStack(spacing: 7) {
            // MARK: - 1. Native App Icon with Active Audio Indicator (Pure display, no artificial borders)
            ZStack(alignment: .bottomTrailing) {
                AppIconView(icon: process.icon, size: 26)
                
                if process.isPlayingAudio {
                    audioIndicatorDot
                        .offset(x: 2, y: 2)
                }
            }
            .frame(width: 26, height: 26)
            
            // MARK: - 2. App Name & Clean Output Device Pill
            VStack(alignment: .leading, spacing: 2) {
                Text(cleanAppName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(process.isMuted ? Color.secondary.opacity(0.6) : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                if let onOutputDeviceChange = onOutputDeviceChange, !availableDevices.isEmpty {
                    Button(action: {
                        isShowingDevicePopover.toggle()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: currentDevice?.systemIconName ?? (defaultDevice?.systemIconName ?? "speaker.wave.2.fill"))
                                .font(.system(size: 7.5))
                            
                            Text(currentDevice?.name ?? "Default Output")
                                .font(.system(size: 9.5, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            Image(systemName: "chevron.down")
                                .font(.system(size: 6, weight: .bold))
                                .opacity(0.65)
                        }
                        .foregroundColor(process.outputDeviceUID != nil ? Color.accentColor : (isDeviceHovered ? Color.primary : Color.primary.opacity(0.85)))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    process.outputDeviceUID != nil
                                        ? Color.accentColor.opacity(isDeviceHovered ? 0.30 : 0.18)
                                        : Color.white.opacity(isDeviceHovered ? 0.16 : 0.07)
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(
                                            process.outputDeviceUID != nil
                                                ? Color.accentColor.opacity(isDeviceHovered ? 0.55 : 0.35)
                                                : Color.white.opacity(isDeviceHovered ? 0.22 : 0.10),
                                            lineWidth: 0.7
                                        )
                                )
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointingHandOnHover()
                    .onHover { h in
                        isDeviceHovered = h
                    }
                    .animation(.easeInOut(duration: 0.12), value: isDeviceHovered)
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
            .frame(width: 106, alignment: .leading)
            
            Spacer(minLength: 6)
            
            // MARK: - 3. Mute Button (20x20)
            Button(action: onMuteToggle) {
                Image(systemName: process.isMuted ? "speaker.slash.fill" : (localVolume == 0 ? "speaker.fill" : (localVolume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(process.isMuted ? Color.red : (isMuteHovered ? Color.primary : Color.secondary))
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(
                                process.isMuted
                                    ? Color.red.opacity(isMuteHovered ? 0.28 : 0.16)
                                    : (isMuteHovered ? Color.white.opacity(0.12) : Color.clear)
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        process.isMuted
                                            ? Color.red.opacity(isMuteHovered ? 0.45 : 0.22)
                                            : (isMuteHovered ? Color.white.opacity(0.18) : Color.clear),
                                        lineWidth: 0.6
                                    )
                            )
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .pointingHandOnHover()
            .onHover { h in
                isMuteHovered = h
            }
            .animation(.easeInOut(duration: 0.12), value: isMuteHovered)
            
            // MARK: - 4. Volume Slider (105x18)
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
            .frame(width: 105, height: 18)
            
            // MARK: - 5. Percentage Label (34)
            Text("\(Int(round(localVolume * 100)))%")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(process.isMuted ? Color.secondary.opacity(0.4) : (localVolume > 1.0 ? Color.orange : Color.secondary))
                .frame(width: 34, alignment: .trailing)
            
            // MARK: - 6. Optional Remove Button (14x14)
            Group {
                if let onRemove = onRemove, isHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(isRemoveHovered ? Color.red.opacity(0.9) : Color.secondary.opacity(0.65))
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
                        isRemoveHovered = h
                    }
                    .animation(.easeInOut(duration: 0.12), value: isRemoveHovered)
                } else {
                    Color.clear
                        .frame(width: 14, height: 14)
                }
            }
            .frame(width: 14, height: 14)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.065) : Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
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
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
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
    .frame(width: 390)
    .background(Color(red: 0.13, green: 0.13, blue: 0.14))
}
