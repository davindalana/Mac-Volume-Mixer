import SwiftUI

/// Container tampilan utama untuk popup menu bar (Popover).
/// Menggabungkan header, kontrol master, pencarian, list aplikasi aktif, dan footer aksi aplikasi.
public struct PopoverView: View {
    @ObservedObject public var viewModel: MixerViewModel
    @State private var isSpinningRefresh: Bool = false
    
    public init(viewModel: MixerViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerView
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            // MARK: - Permission Alert Banner (if needed)
            if viewModel.permissionStatus != .authorized {
                permissionBannerView
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            
            // MARK: - Master Volume Card
            MasterVolumeView(viewModel: viewModel)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            
            // MARK: - Search Field
            searchBarView
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            
            // MARK: - Section Title
            HStack {
                Text("APPLICATIONS (\(viewModel.filteredProcesses.count))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                let activeCount = viewModel.processes.filter { $0.isPlayingAudio }.count
                if activeCount > 0 {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                        Text("\(activeCount) active")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            
            // MARK: - Scrollable Apps List
            ScrollView {
                LazyVStack(spacing: 2) {
                    if viewModel.filteredProcesses.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(viewModel.filteredProcesses) { process in
                            AppVolumeRowView(
                                process: process,
                                onVolumeChange: { newVolume in
                                    viewModel.updateVolume(for: process.pid, volume: newVolume)
                                },
                                onMuteToggle: {
                                    viewModel.toggleMute(for: process.pid)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 280)
            
            // MARK: - Divider
            Divider()
                .padding(.top, 4)
            
            // MARK: - Footer
            footerView
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 340)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
                
                Text("Volume Mixer")
                    .font(.system(size: 13, weight: .bold))
            }
            
            Spacer()
            
            // Tombol Refresh
            Button(action: {
                withAnimation(.easeInOut(duration: 0.4)) {
                    isSpinningRefresh = true
                }
                viewModel.refresh()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isSpinningRefresh = false
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isSpinningRefresh ? 360 : 0))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Refresh Audio Processes")
        }
    }
    
    private var permissionBannerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 13))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Audio Permission Required")
                    .font(.system(size: 11, weight: .bold))
                Text("Allow Screen & Audio Recording to mix per-app audio.")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Grant") {
                viewModel.requestPermissions()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var searchBarView: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            TextField("Filter apps...", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            
            if !viewModel.searchQuery.isEmpty {
                Button(action: {
                    viewModel.searchQuery = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 26))
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.top, 16)
            
            Text(viewModel.searchQuery.isEmpty ? "No active audio apps" : "No apps match \"\(viewModel.searchQuery)\"")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("Launch an app like Music, Safari, or Spotify to adjust its volume.")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var footerView: some View {
        HStack {
            // Indikator status Engine
            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.isMonitoring ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                
                Text(viewModel.isMonitoring ? "CoreAudio Tap Active" : "Paused")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Tombol Izin (jika diperlukan)
            if viewModel.permissionStatus != .authorized {
                Button(action: {
                    viewModel.requestPermissions()
                }) {
                    Text("Permissions")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                
                Text("•")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            // Tombol Quit
            Button(action: {
                viewModel.quitApp()
            }) {
                HStack(spacing: 3) {
                    Text("Quit")
                        .font(.system(size: 10, weight: .medium))
                    Text("⌘Q")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

#Preview {
    PopoverView(viewModel: MixerViewModel())
}
