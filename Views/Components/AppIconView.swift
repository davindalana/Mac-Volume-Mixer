import SwiftUI
import AppKit

/// Komponen visual untuk menampilkan icon aplikasi macOS dengan ukuran custom,
/// rounded corners, border halus, dan fallback symbol jika icon tidak tersedia.
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
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .fill(
                            LinearGradient(
                                colors: [Color.gray.opacity(0.35), Color.gray.opacity(0.2)],
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
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 1.5, x: 0, y: 1)
    }
}

#Preview {
    HStack(spacing: 16) {
        AppIconView(icon: nil, size: 24)
        AppIconView(icon: NSWorkspace.shared.icon(forFile: "/Applications/Safari.app"), size: 24)
        AppIconView(icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Music.app"), size: 32)
    }
    .padding()
}
