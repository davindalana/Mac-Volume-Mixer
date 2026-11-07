import SwiftUI

/// Antarmuka MenuBar Popover berpenampilan Liquid Glass modern khas macOS Sonoma & Sequoia.
/// Mengadopsi prinsip Glassmorphism Apple: Frosted Glass (`ultraThinMaterial`), border halus,
/// kartu mengambang (floating glass tiles), dan kontrol terintegrasi yang mudah digunakan.
public struct PopoverView: View {
    @ObservedObject public var viewModel: MixerViewModel
    @State private var isSpinningRefresh: Bool = false
    
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
                
                // Master Output Device Capsule (Control Center Style)
                Menu {
                    Section("Output Device") {
                        ForEach(viewModel.outputDevices) { device in
                            Button(action: {
                                viewModel.selectOutputDevice(device)
                            }) {
                                HStack {
                                    Text(device.name)
                                    if device.id == viewModel.selectedOutputDevice?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
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
                    .foregroundColor(.primary.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                            )
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
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
            
            // MARK: - Modern Glass Footer (Unified Controls)
            HStack(alignment: .center) {
                // Settings Menu (Glass Squircle Button)
                Menu {
                    Button("Refresh Audio Processes") {
                        viewModel.refresh()
                    }
                    
                    if viewModel.permissionStatus != .authorized {
                        Button("Audio Permissions...") {
                            viewModel.requestPermissions()
                        }
                    }
                    
                    Button("Setup Safari YouTube...") {
                        viewModel.showSafariGuide()
                    }
                    
                    Button("Restart Mixer") {
                        viewModel.restartApp()
                    }
                    
                    Divider()
                    
                    Button("Quit MacVolumeMixer") {
                        viewModel.quitApp()
                    }
                    .keyboardShortcut("q", modifiers: .command)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                                )
                        )
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Settings & Options")
                
                Spacer()
                
                // "+ Add App" Glass Capsule Button (Unified & Compact)
                Menu {
                    if viewModel.availableRunningApps.isEmpty {
                        Text("No other running apps")
                    } else {
                        ForEach(viewModel.availableRunningApps, id: \.processIdentifier) { app in
                            Button(action: {
                                if let bID = app.bundleIdentifier {
                                    viewModel.addPinnedApp(bundleIdentifier: bID)
                                }
                            }) {
                                HStack {
                                    if let icon = app.icon {
                                        Image(nsImage: icon)
                                    }
                                    Text(app.localizedName ?? "App")
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button("Choose Other App...") {
                        viewModel.chooseAppFromDisk()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("Add App")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .opacity(0.6)
                    }
                    .foregroundColor(.primary.opacity(0.85))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.07))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                            )
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
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
                                ? LinearGradient(colors: [Color.red.opacity(0.28), Color.red.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    viewModel.isMasterMuted ? Color.red.opacity(0.4) : Color.accentColor.opacity(0.38),
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
            .help(viewModel.isMasterMuted ? "Unmute System" : "Mute System")
            
            // Info: System Title & Output Device Subtitle
            VStack(alignment: .leading, spacing: 1.5) {
                Text("System Audio")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(viewModel.isMasterMuted ? Color.secondary.opacity(0.6) : Color.primary)
                    .lineLimit(1)
                
                Text(viewModel.selectedOutputDevice?.name ?? "Speakers")
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundColor(Color.secondary.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 104, alignment: .leading)
            
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
            
            Button("Restart") {
                viewModel.restartApp()
            }
            .font(.system(size: 9.5, weight: .medium))
            .buttonStyle(.bordered)
            .controlSize(.mini)
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
