import SwiftUI
import AppKit

/// Komponen visual untuk menampilkan icon aplikasi macOS secara bersih dan native.
/// Menampilkan icon aplikasi resmi tanpa bingkai atau overlay buatan yang mengganggu.
public struct AppIconView: View {
    public let icon: NSImage?
    public let size: CGFloat
    
    public init(icon: NSImage?, size: CGFloat = 24) {
        self.icon = icon
        self.size = size
    }
    
    public var body: some View {
        Group {
            if let nsImage = icon {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.gray.opacity(0.35), Color.gray.opacity(0.20)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "app.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(size * 0.22)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 16) {
        AppIconView(icon: nil, size: 26)
        AppIconView(icon: NSWorkspace.shared.icon(forFile: "/Applications/Safari.app"), size: 26)
        AppIconView(icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Music.app"), size: 26)
    }
    .padding()
}
