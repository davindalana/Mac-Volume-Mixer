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
        VStack(spacing: 4) {
            // MARK: - Optional Discreet Permission Notice
            if viewModel.permissionStatus != .authorized && !viewModel.isBannerDismissed {
                discreetPermissionBanner
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
            }
            
            // MARK: - Mixer Rows Container
            VStack(spacing: 2) {
                // 1. "System" Row (Master System Hardware Volume)
                systemVolumeRow
                
                // 2. Individual App Rows (Finder, Music, Safari, WhatsApp, etc.)
                ForEach(viewModel.displayProcesses) { process in
                    AppVolumeRowView(
                        process: process,
                        onVolumeChange: { newVolume in
                            viewModel.updateVolume(for: process.pid, volume: newVolume)
                        },
                        onMuteToggle: {
                            viewModel.toggleMute(for: process.pid)
                        },
                        onRemove: (viewModel.pinnedAppBundleIDs.contains(process.bundleIdentifier ?? "")) ? {
                            if let bID = process.bundleIdentifier {
                                viewModel.removePinnedApp(bundleIdentifier: bID)
                            }
                        } : nil
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 4)
            
            // MARK: - Footer Bar (Settings & Add App)
            HStack(alignment: .center) {
                // Settings & Output Device Menu
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
                    
                    Divider()
                    
                    Button("Refresh Audio") {
                        viewModel.refresh()
                    }
                    
                    if viewModel.permissionStatus != .authorized {
                        Button("Audio Permissions...") {
                            viewModel.requestPermissions()
                        }
                    }
                    
                    Button("Restart Mixer") {
                        viewModel.restartApp()
                    }
                    
                    Button("Setup Safari YouTube...") {
                        viewModel.showSafariGuide()
                    }
                    
                    Divider()
                    
                    Button("Quit MacVolumeMixer") {
                        viewModel.quitApp()
                    }
                    .keyboardShortcut("q", modifiers: .command)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.45))
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                Spacer()
                
                // "+ Add App" Button (Persis screenshot)
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
                        Text("Add App")
                            .font(.system(size: 11.5, weight: .regular))
                    }
                    .foregroundColor(Color(white: 0.65))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .frame(width: 345)
        .background(Color(red: 0.125, green: 0.125, blue: 0.13))
        .onAppear {
            viewModel.refresh()
        }
    }
    
    // MARK: - System Volume Row (Master Hardware Control)
    private var systemVolumeRow: some View {
        HStack(spacing: 8) {
            // Speaker Icon representing System Audio
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(white: 0.22))
                    .frame(width: 22, height: 22)
                
                Image(systemName: viewModel.isMasterMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(viewModel.isMasterMuted ? Color(white: 0.45) : Color(white: 0.9))
            }
            .frame(width: 22, height: 22)
            
            Text("System")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(viewModel.isMasterMuted ? Color(white: 0.5) : Color(white: 0.95))
            
            Spacer(minLength: 6)
            
            // Master Mute Button
            Button(action: {
                viewModel.toggleMasterMute()
            }) {
                Image(systemName: viewModel.isMasterMuted ? "speaker.slash.fill" : "speaker.slash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(viewModel.isMasterMuted ? Color(red: 1.0, green: 0.35, blue: 0.35) : Color(white: 0.6))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(viewModel.isMasterMuted ? "Unmute System" : "Mute System")
            
            // Master Volume Slider (0% - 200%, default 100%)
            CustomSlider(
                value: Binding(
                    get: { viewModel.masterVolume },
                    set: { viewModel.updateMasterVolume($0) }
                ),
                maxValue: 2.0,
                baselineValue: 1.0,
                isMuted: viewModel.isMasterMuted,
                accentColor: Color(red: 1.0, green: 0.584, blue: 0.0)
            )
            .frame(width: 120)
            
            // Percentage Label
            Text("\(Int(round(viewModel.masterVolume * 100)))%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(viewModel.isMasterMuted ? Color(white: 0.45) : (viewModel.masterVolume > 1.0 ? Color(red: 1.0, green: 0.75, blue: 0.2) : Color(white: 0.75)))
                .frame(width: 36, alignment: .trailing)
            
            // Placeholder alignment spacing matching remove button
            Spacer().frame(width: 14)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3.5)
    }
    
    // MARK: - Discreet Permission Banner (can be permanently dismissed)
    private var discreetPermissionBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .foregroundColor(Color.orange)
            
            Text("Audio recording permission recommended.")
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.8))
            
            Spacer()
            
            Button("Settings") {
                viewModel.requestPermissions()
            }
            .font(.system(size: 9.5, weight: .medium))
            .buttonStyle(.bordered)
            .controlSize(.mini)
            
            Button(action: {
                viewModel.dismissPermissionBanner()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(white: 0.6))
                    .padding(2)
            }
            .buttonStyle(.plain)
            .help("Dismiss permanently")
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.12))
        )
    }
}

#Preview {
    PopoverView(viewModel: MixerViewModel())
}
