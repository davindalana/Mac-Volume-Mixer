import SwiftUI

/// Kontrol Master Volume dan Output Device Selector.
/// Menampilkan slider master sistem, tombol toggle mute master, dan menu pilihan perangkat audio keluaran.
public struct MasterVolumeView: View {
    @ObservedObject public var viewModel: MixerViewModel
    
    public init(viewModel: MixerViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // MARK: - Output Device Selector Header
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.selectedOutputDevice?.systemIconName ?? "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                    
                    Text("Output:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Device Picker Menu
                Menu {
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
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.selectedOutputDevice?.name ?? "Select Device")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(5)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            
            // MARK: - Master Volume Slider Row
            HStack(spacing: 10) {
                // Speaker icon
                Image(systemName: viewModel.isMasterMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                    .font(.system(size: 13))
                    .foregroundColor(viewModel.isMasterMuted ? .red : .accentColor)
                    .frame(width: 20)
                
                // Slider
                CustomSlider(
                    value: Binding(
                        get: { viewModel.masterVolume },
                        set: { viewModel.updateMasterVolume($0) }
                    ),
                    isMuted: viewModel.isMasterMuted,
                    accentColors: [Color.blue, Color.purple]
                )
                
                // Percentage Text
                Text(viewModel.isMasterMuted ? "Muted" : "\(Int(round(viewModel.masterVolume * 100)))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(width: 42, alignment: .trailing)
                
                // Master Mute Button
                Button(action: {
                    viewModel.toggleMasterMute()
                }) {
                    Image(systemName: viewModel.isMasterMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12))
                        .foregroundColor(viewModel.isMasterMuted ? .red : .secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(viewModel.isMasterMuted ? "Unmute Master" : "Mute Master")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

#Preview {
    MasterVolumeView(viewModel: MixerViewModel())
        .padding()
        .frame(width: 320)
}
