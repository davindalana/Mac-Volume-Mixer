import SwiftUI

/// Antarmuka MenuBar Popover berpenampilan Liquid Glass modern khas macOS Sonoma & Sequoia.
/// Mengadopsi prinsip Glassmorphism Apple: Frosted Glass (`ultraThinMaterial`), border halus,
/// kartu mengambang (floating glass tiles), dan kontrol terintegrasi yang mudah digunakan.
public struct PopoverView: View {
    @ObservedObject public var viewModel: MixerViewModel
    @State private var isSpinningRefresh: Bool = false
    @State private var isShowingSettingsPopover: Bool = false
    @State private var isShowingAddAppPopover: Bool = false
    @State private var isShowingMasterDevicePopover: Bool = false
    @State private var isShowingSystemRowDevicePopover: Bool = false
    
    // Hover states for smooth background feedback without text popups
    @State private var isMasterDeviceHovered: Bool = false
    @State private var isSystemMuteHovered: Bool = false
    @State private var isSystemDeviceHovered: Bool = false
    @State private var isSettingsHovered: Bool = false
    @State private var isAddAppHovered: Bool = false
    
    public init(viewModel: MixerViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Required Permission Notice
            if viewModel.permissionStatus != .authorized {
                discreetPermissionBanner
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            
            // MARK: - Header Bar (Control Center Glass Header)
            HStack(spacing: 8) {
                if let appIcon = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .shadow(color: Color.black.opacity(0.2), radius: 2, y: 1)
                }
                
                Text("Sound")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Master Output Device Capsule (Control Center Style with Animated Popover)
                Button(action: {
                    isShowingMasterDevicePopover.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.selectedOutputDevice?.systemIconName ?? "speaker.wave.2.fill")
                            .font(.system(size: 9.5))
                        Text(viewModel.selectedOutputDevice?.name ?? "Speakers")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .opacity(0.6)
                    }
                    .foregroundColor(isMasterDeviceHovered ? Color.primary : Color.primary.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(isMasterDeviceHovered ? 0.18 : 0.08))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(isMasterDeviceHovered ? 0.25 : 0.12), lineWidth: 0.8)
                            )
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointingHandOnHover()
                .onHover { h in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isMasterDeviceHovered = h
                    }
                }
                .popover(isPresented: $isShowingMasterDevicePopover, arrowEdge: .bottom) {
                    DevicePickerPopover(
                        appName: "Output Master Sistem",
                        availableDevices: viewModel.outputDevices,
                        currentDeviceUID: viewModel.selectedOutputDevice?.uid,
                        onSelect: { selectedDev in
                            if let dev = selectedDev {
                                viewModel.selectOutputDevice(dev)
                            }
                        },
                        onClose: {
                            isShowingMasterDevicePopover = false
                        }
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)
            
            // MARK: - Master System Volume Glass Tile
            systemVolumeRow
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            
            // MARK: - Apps Section Header
            HStack {
                Text("APPS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.55))
                    .kerning(0.8)
                
                Spacer()
                
                if !viewModel.displayProcesses.isEmpty {
                    Text("\(viewModel.displayProcesses.count)")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)
            
            // MARK: - App Volume Rows Section
            if viewModel.displayProcesses.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No other active sound streams")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.9))
                    Text("Sound from active apps will appear here automatically")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.white.opacity(0.04), lineWidth: 0.6)
                        )
                )
                .padding(.horizontal, 12)
            } else if viewModel.displayProcesses.count > 5 {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 4) {
                        ForEach(viewModel.displayProcesses) { process in
                            AppVolumeRowView(
                                process: process,
                                availableDevices: viewModel.outputDevices,
                                onVolumeChange: { newVolume in
                                    viewModel.updateVolume(for: process, volume: newVolume)
                                },
                                onMuteToggle: {
                                    viewModel.toggleMute(for: process)
                                },
                                onOutputDeviceChange: { selectedDev in
                                    viewModel.setOutputDevice(for: process, device: selectedDev)
                                },
                                onRemove: (viewModel.pinnedAppBundleIDs.contains(process.bundleIdentifier ?? "")) ? {
                                    if let bID = process.bundleIdentifier {
                                        viewModel.removePinnedApp(bundleIdentifier: bID)
                                    }
                                } : nil
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxHeight: 250)
            } else {
                VStack(spacing: 4) {
                    ForEach(viewModel.displayProcesses) { process in
                        AppVolumeRowView(
                            process: process,
                            availableDevices: viewModel.outputDevices,
                            onVolumeChange: { newVolume in
                                viewModel.updateVolume(for: process, volume: newVolume)
                            },
                            onMuteToggle: {
                                viewModel.toggleMute(for: process)
                            },
                            onOutputDeviceChange: { selectedDev in
                                viewModel.setOutputDevice(for: process, device: selectedDev)
                            },
                            onRemove: (viewModel.pinnedAppBundleIDs.contains(process.bundleIdentifier ?? "")) ? {
                                if let bID = process.bundleIdentifier {
                                    viewModel.removePinnedApp(bundleIdentifier: bID)
                                }
                            } : nil
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
            
            // MARK: - Subtle Glass Divider
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.8)
                .padding(.horizontal, 12)
                .padding(.top, 7)
                .padding(.bottom, 5)
            
            // MARK: - Modern Glass Footer (Animated Popovers & Hover Feedback)
            HStack(alignment: .center) {
                // Settings Menu Button (Animated Popover with Clean Glass Hover)
                Button(action: {
                    isShowingSettingsPopover.toggle()
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11.5))
                        .foregroundColor(isSettingsHovered ? .primary : .secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                .fill(Color.white.opacity(isSettingsHovered ? 0.20 : 0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                        .stroke(Color.white.opacity(isSettingsHovered ? 0.28 : 0.14), lineWidth: 0.8)
                                )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandOnHover()
                .onHover { h in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isSettingsHovered = h
                    }
                }
                .popover(isPresented: $isShowingSettingsPopover, arrowEdge: .top) {
                    SettingsMenuPopover(viewModel: viewModel, onClose: {
                        isShowingSettingsPopover = false
                    })
                }
                
                Spacer()
                
                // "+ Add App" Glass Capsule Button (Animated Popover with Clean Glass Hover)
                Button(action: {
                    isShowingAddAppPopover.toggle()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("Add App")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .opacity(0.65)
                    }
                    .foregroundColor(Color.primary.opacity(isAddAppHovered ? 1.0 : 0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(isAddAppHovered ? 0.20 : 0.09))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(isAddAppHovered ? 0.28 : 0.15), lineWidth: 0.8)
                            )
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointingHandOnHover()
                .onHover { h in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isAddAppHovered = h
                    }
                }
                .popover(isPresented: $isShowingAddAppPopover, arrowEdge: .top) {
                    AddAppPopover(viewModel: viewModel, onClose: {
                        isShowingAddAppPopover = false
                    })
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(width: 380)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.07),
                        Color.white.opacity(0.02),
                        Color.black.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .onAppear {
            viewModel.refresh()
        }
    }
    
    // MARK: - System Master Volume Card (Control Center Glass Tile)
    private var systemVolumeRow: some View {
        HStack(spacing: 9) {
            // Interactive Master Mute Button / Vibrant Glass Squircle
            Button(action: {
                viewModel.toggleMasterMute()
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            viewModel.isMasterMuted
                                ? LinearGradient(
                                    colors: [Color.red.opacity(isSystemMuteHovered ? 0.40 : 0.28), Color.red.opacity(isSystemMuteHovered ? 0.22 : 0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [Color.accentColor.opacity(isSystemMuteHovered ? 0.50 : 0.35), Color.accentColor.opacity(isSystemMuteHovered ? 0.26 : 0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    viewModel.isMasterMuted
                                        ? Color.red.opacity(isSystemMuteHovered ? 0.60 : 0.4)
                                        : Color.accentColor.opacity(isSystemMuteHovered ? 0.58 : 0.38),
                                    lineWidth: 0.8
                                )
                        )
                    
                    Image(systemName: viewModel.isMasterMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(viewModel.isMasterMuted ? Color.red : Color.accentColor)
                }
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandOnHover()
            .onHover { h in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isSystemMuteHovered = h
                }
            }
            
            // Info: System Title & Clickable Output Device Pill
            VStack(alignment: .leading, spacing: 2) {
                Text("System Audio")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(viewModel.isMasterMuted ? Color.secondary.opacity(0.6) : Color.primary)
                    .lineLimit(1)
                
                Button(action: {
                    isShowingSystemRowDevicePopover.toggle()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: viewModel.selectedOutputDevice?.systemIconName ?? "speaker.wave.2.fill")
                            .font(.system(size: 7.5))
                        Text(viewModel.selectedOutputDevice?.name ?? "Speakers")
                            .font(.system(size: 9.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 6, weight: .bold))
                            .opacity(0.6)
                    }
                    .foregroundColor(isSystemDeviceHovered ? Color.primary : Color.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(isSystemDeviceHovered ? 0.18 : 0.06))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(isSystemDeviceHovered ? 0.25 : 0.12), lineWidth: 0.8)
                            )
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointingHandOnHover()
                .onHover { h in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isSystemDeviceHovered = h
                    }
                }
                .popover(isPresented: $isShowingSystemRowDevicePopover, arrowEdge: .bottom) {
                    DevicePickerPopover(
                        appName: "Output Sistem",
                        availableDevices: viewModel.outputDevices,
                        currentDeviceUID: viewModel.selectedOutputDevice?.uid,
                        onSelect: { selectedDev in
                            if let dev = selectedDev {
                                viewModel.selectOutputDevice(dev)
                            }
                        },
                        onClose: {
                            isShowingSystemRowDevicePopover = false
                        }
                    )
                }
            }
            .frame(width: 110, alignment: .leading)
            
            Spacer(minLength: 4)
            
            // Master Volume Slider
            CustomSlider(
                value: Binding(
                    get: { viewModel.masterVolume },
                    set: { viewModel.updateMasterVolume($0) }
                ),
                maxValue: 2.0,
                baselineValue: 1.0,
                isMuted: viewModel.isMasterMuted,
                accentColor: Color.accentColor
            )
            .frame(width: 100, height: 18)
            
            // Percentage Label
            Text("\(Int(round(viewModel.masterVolume * 100)))%")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(viewModel.isMasterMuted ? Color.secondary.opacity(0.5) : (viewModel.masterVolume > 1.0 ? Color.orange : Color.secondary))
                .frame(width: 34, alignment: .trailing)
            
            // Placeholder alignment spacing matching remove button
            Color.clear
                .frame(width: 14, height: 14)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                )
        )
    }
    
    // MARK: - Discreet Permission Banner
    private var discreetPermissionBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(Color.orange)
            
            Text("Izin Audio Sistem diperlukan untuk kontrol volume.")
                .font(.system(size: 10.5))
                .foregroundColor(Color(white: 0.9))
            
            Spacer()
            
            Button("Aktifkan Izin") {
                viewModel.requestPermissions()
            }
            .font(.system(size: 9.5, weight: .semibold))
            .buttonStyle(.borderedProminent)
            .tint(Color.orange)
            .controlSize(.mini)
            .pointingHandOnHover()
            
            Button("Restart") {
                viewModel.restartApp()
            }
            .font(.system(size: 9.5, weight: .medium))
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .pointingHandOnHover()
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.orange.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.orange.opacity(0.28), lineWidth: 0.8)
                )
        )
    }
}

#Preview {
    PopoverView(viewModel: MixerViewModel())
}
