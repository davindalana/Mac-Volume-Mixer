import SwiftUI
import AppKit

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
    /// Menampilkan kursor tangan (pointing hand) saat mouse diarahkan ke elemen ini.
    func pointingHandOnHover() -> some View {
        self.modifier(PointingHandModifier())
    }
}
