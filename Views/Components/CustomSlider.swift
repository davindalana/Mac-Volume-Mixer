import SwiftUI

/// Slider kustom dengan estetika modern macOS (track ramping, gradient fill, drag gesture interaktif).
public struct CustomSlider: View {
    @Binding public var value: Float
    public var isMuted: Bool
    public var accentColors: [Color]
    public var onEditingChanged: ((Bool) -> Void)?
    
    @State private var isHovered: Bool = false
    @State private var isDragging: Bool = false
    
    public init(
        value: Binding<Float>,
        isMuted: Bool = false,
        accentColors: [Color] = [Color.blue, Color.cyan],
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self._value = value
        self.isMuted = isMuted
        self.accentColors = accentColors
        self.onEditingChanged = onEditingChanged
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let progress = CGFloat(max(0.0, min(1.0, value)))
            let filledWidth = totalWidth * progress
            let trackHeight: CGFloat = isHovered || isDragging ? 7 : 5
            
            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: trackHeight)
                
                // Progress Track
                Capsule()
                    .fill(
                        isMuted ?
                            LinearGradient(colors: [Color.gray.opacity(0.5), Color.gray.opacity(0.4)], startPoint: .leading, endPoint: .trailing) :
                            LinearGradient(colors: accentColors, startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(0, filledWidth), height: trackHeight)
                
                // Thumb Indicator
                Circle()
                    .fill(Color.white)
                    .frame(width: isHovered || isDragging ? 14 : 10, height: isHovered || isDragging ? 14 : 10)
                    .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                    )
                    .offset(x: max(0, min(totalWidth - (isHovered || isDragging ? 14 : 10), filledWidth - (isHovered || isDragging ? 7 : 5))))
                    .opacity(isHovered || isDragging || value > 0 ? 1.0 : 0.6)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged?(true)
                        }
                        let newProgress = Float(gesture.location.x / totalWidth)
                        value = max(0.0, min(1.0, newProgress))
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged?(false)
                    }
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
        }
        .frame(height: 18)
    }
}

#Preview {
    VStack(spacing: 20) {
        CustomSlider(value: .constant(0.65), isMuted: false)
        CustomSlider(value: .constant(0.30), isMuted: true)
        CustomSlider(value: .constant(1.0), isMuted: false, accentColors: [Color.purple, Color.pink])
    }
    .padding()
    .frame(width: 250)
}
