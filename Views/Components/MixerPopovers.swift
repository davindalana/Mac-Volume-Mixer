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
            DevicePickerItemRow(
                title: "Default Sistem",
                subtitle: defaultDevice?.name ?? "Speakers",
                iconName: defaultDevice?.systemIconName ?? "speaker.wave.2.fill",
                isSelected: currentDeviceUID == nil,
                action: {
                    onSelect(nil)
                    onClose()
                }
            )
            
            // 2. Other Available Devices
            if !availableDevices.isEmpty {
                Divider().opacity(0.4)
                
                Text("Perangkat Audio Lainnya")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 6)
                
                ForEach(availableDevices) { device in
                    DevicePickerItemRow(
                        title: device.name,
                        subtitle: nil,
                        iconName: device.systemIconName,
                        isSelected: (device.uid == currentDeviceUID),
                        action: {
                            onSelect(device)
                            onClose()
                        }
                    )
                }
            }
        }
        .padding(10)
        .frame(width: 230)
    }
}

private struct DevicePickerItemRow: View {
    let title: String
    let subtitle: String?
    let iconName: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .accentColor : (isHovered ? .primary : .secondary))
                    .frame(width: 18)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .primary : (isHovered ? .primary : .secondary))
                        .lineLimit(1)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                
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
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(isHovered ? 0.22 : 0.14)
                            : (isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.02))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(
                                isSelected
                                    ? Color.accentColor.opacity(isHovered ? 0.45 : 0.25)
                                    : (isHovered ? Color.white.opacity(0.18) : Color.clear),
                                lineWidth: 0.6
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = h
            }
        }
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
            
            SettingsMenuItemRow(title: "Segarkan Proses Audio", icon: "arrow.clockwise") {
                viewModel.refresh()
                onClose()
            }
            
            if viewModel.permissionStatus != .authorized {
                SettingsMenuItemRow(title: "Izin Audio Sistem...", icon: "lock.shield", accent: .orange) {
                    viewModel.requestPermissions()
                    onClose()
                }
            }
            
            SettingsMenuItemRow(title: "Restart Mixer", icon: "arrow.triangle.2.circlepath") {
                viewModel.restartApp()
                onClose()
            }
            
            Divider().opacity(0.4)
            
            SettingsMenuItemRow(title: "Keluar dari MacVolumeMixer", icon: "power", accent: .red) {
                viewModel.quitApp()
            }
        }
        .padding(8)
        .frame(width: 215)
    }
}

private struct SettingsMenuItemRow: View {
    let title: String
    let icon: String
    var accent: Color = .primary
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(accent == .primary ? (isHovered ? .primary : .secondary) : accent)
                    .frame(width: 18)
                
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(accent == .primary ? (isHovered ? .primary : .secondary.opacity(0.9)) : accent)
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isHovered
                            ? (accent == .red ? Color.red.opacity(0.18) : Color.white.opacity(0.12))
                            : Color.white.opacity(0.02)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isHovered ? Color.white.opacity(0.16) : Color.clear, lineWidth: 0.6)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = h
            }
        }
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
                            AddAppItemRow(
                                name: app.localizedName ?? "App",
                                icon: app.icon,
                                action: {
                                    if let bID = app.bundleIdentifier {
                                        viewModel.addPinnedApp(bundleIdentifier: bID)
                                    }
                                    onClose()
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
            
            Divider().opacity(0.4)
            
            SettingsMenuItemRow(
                title: "Pilih Aplikasi Lain dari Disk...",
                icon: "folder.badge.plus",
                accent: .accentColor,
                action: {
                    viewModel.chooseAppFromDisk()
                    onClose()
                }
            )
        }
        .padding(10)
        .frame(width: 245)
    }
}

private struct AddAppItemRow: View {
    let name: String
    let icon: NSImage?
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "app.fill")
                        .frame(width: 18, height: 18)
                }
                
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isHovered ? .primary : .primary.opacity(0.9))
                    .lineLimit(1)
                
                Spacer()
                
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(isHovered ? .accentColor : .accentColor.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isHovered ? Color.white.opacity(0.16) : Color.clear, lineWidth: 0.6)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = h
            }
        }
    }
}
