import SwiftUI

/// Antarmuka MenuBar Popover berpenampilan elegan dan modern (SoundSource dark aesthetic).
/// Menampilkan kontrol Master "Other Apps", baris aplikasi individual (Finder, Music, Safari, WhatsApp, dll),
/// serta tombol "+ Add App" untuk menambah konfigurasi aplikasi sesuai referensi gambar.
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
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            
            // MARK: - Header Title / Status Bar
            HStack(spacing: 7) {
                if let appIcon = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 17, height: 17)
                }
                
                Text("Sound")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Master Output Device Menu (Control Center style)
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
                            .font(.system(size: 7))
                            .opacity(0.6)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
            
            // MARK: - System Master Volume Card
            systemVolumeRow
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            
            Divider()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .opacity(0.5)
            
            // MARK: - App Volume Rows Section
            if viewModel.displayProcesses.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No other active sound streams")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else if viewModel.displayProcesses.count > 5 {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 2) {
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
                    .padding(.horizontal, 10)
                }
                .frame(maxHeight: 240)
            } else {
                VStack(spacing: 2) {
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
                .padding(.horizontal, 10)
            }
            
            Divider()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .opacity(0.5)
            
            // MARK: - Modern Minimalist Footer
            HStack(alignment: .center) {
                // Settings Menu
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
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                Spacer()
                
                // "+ Add App" Button
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
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 8.5, weight: .semibold))
                        Text("Add App")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
        .frame(width: 375)
        .background(
            ZStack {
                Rectangle().fill(Material.ultraThin)
                Color.black.opacity(0.08)
            }
        )
        .onAppear {
            viewModel.refresh()
        }
    }
    
    // MARK: - System Volume Row (Master Hardware Control)
    private var systemVolumeRow: some View {
        HStack(spacing: 8) {
            // Speaker Icon representing System Audio
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 24, height: 24)
                
                Image(systemName: viewModel.isMasterMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(viewModel.isMasterMuted ? Color.secondary.opacity(0.6) : Color.accentColor)
            }
            .frame(width: 24, height: 24)
            
            // Info: Name & Output Device Selector
            VStack(alignment: .leading, spacing: 2) {
                Text("System")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(viewModel.isMasterMuted ? Color.secondary.opacity(0.6) : Color.primary)
                    .lineLimit(1)
                
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
                    HStack(spacing: 3) {
                        Image(systemName: viewModel.selectedOutputDevice?.systemIconName ?? "speaker.wave.2")
                            .font(.system(size: 8))
                        Text(viewModel.selectedOutputDevice?.name ?? "Speakers")
                            .font(.system(size: 9.5, weight: .regular))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 6.5))
                            .opacity(0.6)
                    }
                    .foregroundColor(Color.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
                .menuStyle(.borderlessButton)
            }
            .frame(width: 108, alignment: .leading)
            
            Spacer(minLength: 4)
            
            // Master Mute Button
            Button(action: {
                viewModel.toggleMasterMute()
            }) {
                Image(systemName: viewModel.isMasterMuted ? "speaker.slash.fill" : "speaker.wave.2")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(viewModel.isMasterMuted ? Color.red.opacity(0.85) : Color.secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .fill(viewModel.isMasterMuted ? Color.red.opacity(0.14) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(viewModel.isMasterMuted ? "Unmute System" : "Mute System")
            
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
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundColor(viewModel.isMasterMuted ? Color.secondary.opacity(0.5) : (viewModel.masterVolume > 1.0 ? Color.orange : Color.secondary))
                .frame(width: 34, alignment: .trailing)
            
            // Placeholder alignment spacing matching remove button
            Color.clear
                .frame(width: 14, height: 14)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.035))
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
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.18))
        )
    }
}

#Preview {
    PopoverView(viewModel: MixerViewModel())
}
