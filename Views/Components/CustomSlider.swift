import SwiftUI
import AppKit

/// Slider kustom berpenampilan Liquid Glass khas macOS Sonoma & Sequoia.
/// Mendukung rentang volume hingga 200% (2.0) dengan titik dasar 100% (1.0) di tengah,
/// dilengkapi visual Liquid Glass: track frosted glass translucency, specular highlight,
/// dual-tone gradient fill (Apple Accent Blue & Warm Amber Boost), glass unity notch,
/// Apple frosted circular knob dengan multi-layer shadow, magnet snap, double-click reset, dan scroll wheel.
public struct CustomSlider: NSViewRepresentable {
    @Binding public var value: Float
    public var maxValue: Float
    public var baselineValue: Float
    public var isMuted: Bool
    public var accentColor: Color
    public var onEditingChanged: ((Bool) -> Void)?
    
    public init(
        value: Binding<Float>,
        maxValue: Float = 2.0,
        baselineValue: Float = 1.0,
        isMuted: Bool = false,
        accentColor: Color = Color.accentColor,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self._value = value
        self.maxValue = maxValue
        self.baselineValue = baselineValue
        self.isMuted = isMuted
        self.accentColor = accentColor
        self.onEditingChanged = onEditingChanged
    }
    
    public func makeNSView(context: Context) -> MacSliderNSView {
        let view = MacSliderNSView()
        view.maxValue = maxValue
        view.baselineValue = baselineValue
        view.value = value
        view.isMuted = isMuted
        view.accentColor = NSColor(accentColor)
        view.onValueChanged = { newVal in
            self.value = newVal
        }
        view.onEditingChanged = onEditingChanged
        return view
    }
    
    public func updateNSView(_ nsView: MacSliderNSView, context: Context) {
        nsView.maxValue = maxValue
        nsView.baselineValue = baselineValue
        if !nsView.isCurrentlyDragging {
            nsView.value = value
        }
        nsView.isMuted = isMuted
        nsView.accentColor = NSColor(accentColor)
    }
}

/// Custom NSView dengan rendering Liquid Glass (Frosted Glass Capsule, Specular Rim, Ambient Glow)
public final class MacSliderNSView: NSView {
    public var maxValue: Float = 2.0 {
        didSet { needsDisplay = true }
    }
    
    public var baselineValue: Float = 1.0 {
        didSet { needsDisplay = true }
    }
    
    public var value: Float = 1.0 {
        didSet {
            if value != oldValue {
                needsDisplay = true
            }
        }
    }
    
    public var isMuted: Bool = false {
        didSet {
            if isMuted != oldValue {
                needsDisplay = true
            }
        }
    }
    
    public var accentColor: NSColor = NSColor.controlAccentColor {
        didSet { needsDisplay = true }
    }
    
    // Warm Liquid Amber untuk volume boost (> 100%)
    public var boostColor: NSColor = NSColor(red: 1.0, green: 0.60, blue: 0.14, alpha: 1.0) {
        didSet { needsDisplay = true }
    }
    
    public var onValueChanged: ((Float) -> Void)?
    public var onEditingChanged: ((Bool) -> Void)?
    
    // Native macOS Control Center capsule slider dimensions
    private let knobWidth: CGFloat = 8.0
    private let knobHeight: CGFloat = 16.0
    private let trackHeight: CGFloat = 6.0
    private var isDragging: Bool = false
    private var isHovered: Bool = false
    public var isCurrentlyDragging: Bool { isDragging }
    
    public override var isFlipped: Bool { true }
    
    public override var intrinsicContentSize: NSSize {
        return NSSize(width: 105, height: 18)
    }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    public override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }
    
    public override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }
    
    public override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let halfKnobW = knobWidth / 2
        let trackWidth = bounds.width - knobWidth
        let trackY = (bounds.height - trackHeight) / 2
        let trackRect = CGRect(x: halfKnobW, y: trackY, width: max(0, trackWidth), height: trackHeight)
        let cornerR = trackHeight / 2
        let bgPath = CGPath(roundedRect: trackRect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)
        
        // ---------------------------------------------------------
        // 1. LIQUID GLASS BACKGROUND TROUGH (Frosted Translucent Groove)
        // ---------------------------------------------------------
        context.saveGState()
        // Translucent dark-glass base fill
        context.addPath(bgPath)
        context.setFillColor(NSColor(white: 0.12, alpha: isHovered ? 0.65 : 0.50).cgColor)
        context.fillPath()
        
        // Subtle inner ambient shadow inside trough
        context.addPath(bgPath)
        context.setStrokeColor(NSColor(white: 0.0, alpha: 0.35).cgColor)
        context.setLineWidth(0.8)
        context.strokePath()
        
        // Glass specular top-edge illumination (Frosted Glass Rim)
        context.addPath(bgPath)
        context.setStrokeColor(NSColor(white: 1.0, alpha: isHovered ? 0.20 : 0.12).cgColor)
        context.setLineWidth(0.6)
        context.strokePath()
        context.restoreGState()
        
        // ---------------------------------------------------------
        // 2. GLASS UNITY TICK NOTCH (100% / 1.0 Baseline Mark)
        // ---------------------------------------------------------
        let baselineNorm = CGFloat(baselineValue / maxValue)
        let tickX = halfKnobW + (trackWidth * baselineNorm)
        let tickHeight = trackHeight - 1.5
        let tickY = (bounds.height - tickHeight) / 2
        let tickRect = CGRect(x: tickX - 0.75, y: tickY, width: 1.5, height: tickHeight)
        let tickPath = CGPath(roundedRect: tickRect, cornerWidth: 0.75, cornerHeight: 0.75, transform: nil)
        
        context.saveGState()
        context.addPath(tickPath)
        context.setFillColor(NSColor(white: 1.0, alpha: isHovered ? 0.35 : 0.22).cgColor)
        context.fillPath()
        context.restoreGState()
        
        // ---------------------------------------------------------
        // 3. LIQUID GLASS ACTIVE PROGRESS FILL (Dynamic Glowing Capsule)
        // ---------------------------------------------------------
        let progress = CGFloat(max(0.0, min(maxValue, value)) / maxValue)
        let effectiveProgress = isMuted ? 0.0 : progress
        
        if effectiveProgress > 0 {
            let activeWidth = max(trackHeight, trackWidth * effectiveProgress)
            let activeRect = CGRect(x: halfKnobW, y: trackY, width: activeWidth, height: trackHeight)
            let activePath = CGPath(roundedRect: activeRect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)
            
            context.saveGState()
            context.addPath(activePath)
            context.clip()
            
            if isMuted {
                // Dimmed muted fill
                context.setFillColor(NSColor(white: 0.30, alpha: 0.40).cgColor)
                context.fill(activeRect)
            } else {
                // Vibrant Liquid Gradient
                let isBoosted = value > baselineValue
                let startColor = accentColor.withAlphaComponent(0.95).cgColor
                let endColor = (isBoosted ? boostColor : accentColor).withAlphaComponent(1.0).cgColor
                
                let colors = [startColor, endColor] as CFArray
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
                    context.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: activeRect.minX, y: activeRect.midY),
                        end: CGPoint(x: activeRect.maxX, y: activeRect.midY),
                        options: []
                    )
                }
                
                // Specular Glass Sheen Highlight on Top Half
                let sheenRect = CGRect(x: activeRect.minX, y: activeRect.minY, width: activeRect.width, height: activeRect.height * 0.45)
                let sheenColors = [
                    NSColor(white: 1.0, alpha: 0.35).cgColor,
                    NSColor(white: 1.0, alpha: 0.05).cgColor
                ] as CFArray
                if let sheenGradient = CGGradient(colorsSpace: colorSpace, colors: sheenColors, locations: [0.0, 1.0]) {
                    context.drawLinearGradient(
                        sheenGradient,
                        start: CGPoint(x: sheenRect.midX, y: sheenRect.minY),
                        end: CGPoint(x: sheenRect.midX, y: sheenRect.maxY),
                        options: []
                    )
                }
            }
            context.restoreGState()
            
            // Soft Outer Ambient Glow if dragging or hovered
            if isDragging && !isMuted {
                context.saveGState()
                context.addPath(activePath)
                let glowColor = (value > baselineValue ? boostColor : accentColor).withAlphaComponent(0.40).cgColor
                context.setShadow(offset: .zero, blur: 4.0, color: glowColor)
                context.setStrokeColor(NSColor(white: 1.0, alpha: 0.40).cgColor)
                context.setLineWidth(0.6)
                context.strokePath()
                context.restoreGState()
            }
        }
        
        // ---------------------------------------------------------
        // 4. APPLE NATIVE OVAL CAPSULE THUMB (macOS Sound / Control Center Style)
        // ---------------------------------------------------------
        let knobX = halfKnobW + (trackWidth * effectiveProgress)
        let knobCenterY = bounds.height / 2
        
        // Elegant vertical oval capsule like macOS Control Center & System Settings
        let currentW: CGFloat = isDragging ? (knobWidth + 1.0) : (isHovered ? (knobWidth + 0.5) : knobWidth)
        let currentH: CGFloat = isDragging ? (knobHeight + 1.5) : (isHovered ? (knobHeight + 0.5) : knobHeight)
        let knobRect = CGRect(x: knobX - (currentW / 2), y: knobCenterY - (currentH / 2), width: currentW, height: currentH)
        let capsuleCorner = currentW / 2
        let capsulePath = CGPath(roundedRect: knobRect, cornerWidth: capsuleCorner, cornerHeight: capsuleCorner, transform: nil)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        // A. Multi-layer Tactile Drop Shadow
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: isDragging ? -2.2 : -1.2),
            blur: isDragging ? 5.0 : 3.0,
            color: NSColor.black.withAlphaComponent(isDragging ? 0.42 : 0.30).cgColor
        )
        context.setFillColor(NSColor(white: 0.98, alpha: 1.0).cgColor)
        context.addPath(capsulePath)
        context.fillPath()
        context.restoreGState()
        
        // B. Pure Apple Frosted Capsule Gradient (Smooth vertical sheen)
        context.saveGState()
        context.addPath(capsulePath)
        context.clip()
        let knobGradientColors = [
            NSColor(white: 1.0, alpha: 1.0).cgColor,
            NSColor(white: 0.96, alpha: 1.0).cgColor,
            NSColor(white: 0.90, alpha: 1.0).cgColor
        ] as CFArray
        if let knobGrad = CGGradient(colorsSpace: colorSpace, colors: knobGradientColors, locations: [0.0, 0.5, 1.0]) {
            context.drawLinearGradient(
                knobGrad,
                start: CGPoint(x: knobRect.midX, y: knobRect.minY),
                end: CGPoint(x: knobRect.midX, y: knobRect.maxY),
                options: []
            )
        }
        
        // Subtle top specular highlight on upper half
        let topSheenRect = CGRect(x: knobRect.minX + 0.6, y: knobRect.minY + 0.5, width: currentW - 1.2, height: (currentH - 1.0) * 0.45)
        let topSheenPath = CGPath(roundedRect: topSheenRect, cornerWidth: (currentW - 1.2) / 2, cornerHeight: (currentW - 1.2) / 2, transform: nil)
        context.addPath(topSheenPath)
        let topSheenColors = [
            NSColor(white: 1.0, alpha: 0.65).cgColor,
            NSColor(white: 1.0, alpha: 0.05).cgColor
        ] as CFArray
        if let sheenGrad = CGGradient(colorsSpace: colorSpace, colors: topSheenColors, locations: [0.0, 1.0]) {
            context.clip()
            context.drawLinearGradient(
                sheenGrad,
                start: CGPoint(x: topSheenRect.midX, y: topSheenRect.minY),
                end: CGPoint(x: topSheenRect.midX, y: topSheenRect.maxY),
                options: []
            )
        }
        context.restoreGState()
        
        // C. Clean Specular Perimeter Stroke
        context.saveGState()
        context.addPath(capsulePath)
        context.setStrokeColor(NSColor(white: 0.0, alpha: 0.14).cgColor)
        context.setLineWidth(0.6)
        context.strokePath()
        
        // Inner white light rim
        let innerRimRect = knobRect.insetBy(dx: 0.6, dy: 0.6)
        let innerRimCorner = max(1.0, (currentW - 1.2) / 2)
        let innerRimPath = CGPath(roundedRect: innerRimRect, cornerWidth: innerRimCorner, cornerHeight: innerRimCorner, transform: nil)
        context.addPath(innerRimPath)
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.70).cgColor)
        context.setLineWidth(0.5)
        context.strokePath()
        context.restoreGState()
    }
    
    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            self.value = baselineValue
            onValueChanged?(baselineValue)
            needsDisplay = true
            return
        }
        
        isDragging = true
        needsDisplay = true
        onEditingChanged?(true)
        updateValue(from: event)
    }
    
    public override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        updateValue(from: event)
    }
    
    public override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            needsDisplay = true
            onEditingChanged?(false)
        }
    }
    
    public override func scrollWheel(with event: NSEvent) {
        let delta = Float(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.005 : 0.05)
        let newValue = max(0.0, min(maxValue, value + delta))
        if newValue != value {
            self.value = newValue
            onValueChanged?(newValue)
        }
    }
    
    private func updateValue(from event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let halfKnobW = knobWidth / 2
        let trackWidth = bounds.width - knobWidth
        guard trackWidth > 0 else { return }
        
        let rawProgress = (location.x - halfKnobW) / trackWidth
        var calcVal = Float(rawProgress) * maxValue
        
        // Magnet Snap ke 100% (baselineValue) jika berada di radius +/- 4%
        if abs(calcVal - baselineValue) < 0.05 {
            calcVal = baselineValue
        }
        
        let clamped = max(0.0, min(maxValue, calcVal))
        self.value = clamped
        onValueChanged?(clamped)
    }
}

#Preview {
    VStack(spacing: 20) {
        CustomSlider(value: .constant(1.0), maxValue: 2.0, isMuted: false)
        CustomSlider(value: .constant(1.5), maxValue: 2.0, isMuted: false)
        CustomSlider(value: .constant(0.5), maxValue: 2.0, isMuted: false)
    }
    .padding()
    .frame(width: 250, height: 120)
    .background(Color(white: 0.15))
}
