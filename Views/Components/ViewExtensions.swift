import SwiftUI
import AppKit

/// Arah kemunculan popup tooltip instan.
public enum TooltipEdge {
    case top
    case bottom
}

/// Modifier untuk menampilkan popup tooltip animasi secara instan saat kursor mouse diarahkan ke elemen di macOS.
public struct InstantTooltipModifier: ViewModifier {
    public let text: String
    public let edge: TooltipEdge
    @State private var isHovered = false
    
    public init(text: String, edge: TooltipEdge = .top) {
        self.text = text
        self.edge = edge
    }
    
    public func body(content: Content) -> some View {
        content
            .overlay(alignment: edge == .top ? .top : .bottom) {
                if isHovered && !text.isEmpty {
                    Text(text)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.primary.opacity(0.95))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
                                )
                                .shadow(color: Color.black.opacity(0.35), radius: 5, x: 0, y: 2)
                        )
                        .fixedSize()
                        .offset(y: edge == .top ? -28 : 28)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .zIndex(999)
                        .allowsHitTesting(false)
                }
            }
            .onHover { hovering in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                    isHovered = hovering
                }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

/// Modifier untuk menampilkan kursor pointing hand saat elemen interaktif di-hover di macOS.
public struct PointingHandModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

public extension View {
    /// Menampilkan popup tooltip animasi instan dan mengubah kursor menjadi tangan saat di-hover.
    func instantTooltip(_ text: String, edge: TooltipEdge = .top) -> some View {
        self.modifier(InstantTooltipModifier(text: text, edge: edge))
    }
    
    /// Menampilkan kursor tangan (pointing hand) saat mouse diarahkan ke elemen ini.
    func pointingHandOnHover() -> some View {
        self.modifier(PointingHandModifier())
    }
}
