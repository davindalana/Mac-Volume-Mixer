import SwiftUI
import AppKit

/// Popover animasi interaktif untuk memilih perangkat output audio suatu aplikasi.
public struct DevicePickerPopover: View {
    public let appName: String
    public let availableDevices: [AudioDevice]
    public let currentDeviceUID: String?
    public let onSelect: (AudioDevice?) -> Void
    public let onClose: () -> Void
    
    public init(
        appName: String,
        availableDevices: [AudioDevice],
        currentDeviceUID: String?,
        onSelect: @escaping (AudioDevice?) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.appName = appName
        self.availableDevices = availableDevices
        self.currentDeviceUID = currentDeviceUID
        self.onSelect = onSelect
        self.onClose = onClose
    }
    
    private var defaultDevice: AudioDevice? {
        availableDevices.first(where: { $0.isDefault })
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pilih Output Audio")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(appName)
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            
            Divider().opacity(0.4)
            
            // 1. System Default Option
            Button(action: {
                onSelect(nil)
                onClose()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: defaultDevice?.systemIconName ?? "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundColor(currentDeviceUID == nil ? .accentColor : .secondary)
                        .frame(width: 18)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Default Sistem")
                            .font(.system(size: 11, weight: currentDeviceUID == nil ? .semibold : .regular))
                            .foregroundColor(currentDeviceUID == nil ? .primary : .secondary)
                        
                        Text(defaultDevice?.name ?? "Speakers")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    if currentDeviceUID == nil {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(currentDeviceUID == nil ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.03))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandOnHover()
            
            if !availableDevices.isEmpty {
                Divider().opacity(0.4)
                
                Text("Perangkat Audio Lainnya")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 6)
                
                ForEach(availableDevices) { device in
                    let isSelected = (device.uid == currentDeviceUID)
                    Button(action: {
                        onSelect(device)
                        onClose()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: device.systemIconName)
                                .font(.system(size: 11))
                                .foregroundColor(isSelected ? .accentColor : .secondary)
                                .frame(width: 18)
                            
                            Text(device.name)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.03))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHandOnHover()
                }
            }
        }
        .padding(10)
        .frame(width: 230)
    }
}

/// Popover animasi interaktif untuk menu Pengaturan & Opsi di Footer.
public struct SettingsMenuPopover: View {
    public let viewModel: MixerViewModel
    public let onClose: () -> Void
    
    public init(viewModel: MixerViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Pengaturan & Opsi")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.top, 4)
            
            Divider().opacity(0.4)
            
            popoverRow(title: "Segarkan Proses Audio", icon: "arrow.clockwise") {
                viewModel.refresh()
                onClose()
            }
            
            if viewModel.permissionStatus != .authorized {
                popoverRow(title: "Izin Audio Sistem...", icon: "lock.shield", accent: .orange) {
                    viewModel.requestPermissions()
                    onClose()
                }
            }
            
            popoverRow(title: "Petunjuk Safari YouTube...", icon: "safari") {
                viewModel.showSafariGuide()
                onClose()
            }
            
            popoverRow(title: "Restart Mixer", icon: "arrow.triangle.2.circlepath") {
                viewModel.restartApp()
                onClose()
            }
            
            Divider().opacity(0.4)
            
            popoverRow(title: "Keluar dari MacVolumeMixer", icon: "power", accent: .red) {
                viewModel.quitApp()
            }
        }
        .padding(8)
        .frame(width: 215)
    }
    
    private func popoverRow(title: String, icon: String, accent: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(accent == .primary ? .secondary : accent)
                    .frame(width: 18)
                
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(accent == .primary ? .primary : accent)
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
    }
}

/// Popover animasi interaktif untuk tombol "+ Add App" di Footer.
public struct AddAppPopover: View {
    public let viewModel: MixerViewModel
    public let onClose: () -> Void
    
    public init(viewModel: MixerViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "plus.app.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.accentColor)
                Text("Tambah Aplikasi ke Mixer")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            
            Divider().opacity(0.4)
            
            if viewModel.availableRunningApps.isEmpty {
                Text("Tidak ada aplikasi lain yang sedang berjalan")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 2) {
                        ForEach(viewModel.availableRunningApps, id: \.processIdentifier) { app in
                            Button(action: {
                                if let bID = app.bundleIdentifier {
                                    viewModel.addPinnedApp(bundleIdentifier: bID)
                                }
                                onClose()
                            }) {
                                HStack(spacing: 8) {
                                    if let icon = app.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 18, height: 18)
                                    } else {
                                        Image(systemName: "app.fill")
                                            .frame(width: 18, height: 18)
                                    }
                                    
                                    Text(app.localizedName ?? "App")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 11))
                                        .foregroundColor(.accentColor)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.white.opacity(0.04))
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .pointingHandOnHover()
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
            
            Divider().opacity(0.4)
            
            Button(action: {
                viewModel.chooseAppFromDisk()
                onClose()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                        .frame(width: 18)
                    
                    Text("Pilih Aplikasi Lain dari Disk...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandOnHover()
        }
        .padding(10)
        .frame(width: 245)
    }
}
