import SwiftUI
import AppKit

/// Slider kustom dengan estetika macOS persis seperti screenshot (SoundSource style).
/// Dibangun menggunakan AppKit `NSViewRepresentable` untuk memastikan interaksi klik (mouseDown),
/// drag (mouseDragged), dan scroll wheel di dalam MenuBarExtra selalu 100% responsif tanpa delay gesture recognizer.
public struct CustomSlider: NSViewRepresentable {
    @Binding public var value: Float
    public var isMuted: Bool
    public var accentColor: Color
    public var onEditingChanged: ((Bool) -> Void)?
    
    public init(
        value: Binding<Float>,
        isMuted: Bool = false,
        accentColor: Color = Color(red: 1.0, green: 0.584, blue: 0.0), // Oranye hangat persis screenshot
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self._value = value
        self.isMuted = isMuted
        self.accentColor = accentColor
        self.onEditingChanged = onEditingChanged
    }
    
    public func makeNSView(context: Context) -> MacSliderNSView {
        let view = MacSliderNSView()
        view.value = value
        view.isMuted = isMuted
        view.accentColor = NSColor(accentColor)
        view.onValueChanged = { newVal in
            DispatchQueue.main.async {
                self.value = newVal
            }
        }
        view.onEditingChanged = onEditingChanged
        return view
    }
    
    public func updateNSView(_ nsView: MacSliderNSView, context: Context) {
        nsView.value = value
        nsView.isMuted = isMuted
        nsView.accentColor = NSColor(accentColor)
    }
}

/// Custom NSView yang menangani rendering dan event mouse langsung di tingkat AppKit.
public final class MacSliderNSView: NSView {
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
    
    public var accentColor: NSColor = NSColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0) {
        didSet { needsDisplay = true }
    }
    
    public var trackColor: NSColor = NSColor(white: 0.32, alpha: 1.0)
    public var onValueChanged: ((Float) -> Void)?
    public var onEditingChanged: ((Bool) -> Void)?
    
    private let knobRadius: CGFloat = 6.0
    private let trackHeight: CGFloat = 3.0
    private var isDragging: Bool = false
    
    public override var isFlipped: Bool { true }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let trackWidth = bounds.width - (knobRadius * 2)
        let trackY = (bounds.height - trackHeight) / 2
        let trackRect = CGRect(x: knobRadius, y: trackY, width: max(0, trackWidth), height: trackHeight)
        
        // 1. Background Track (Abu-abu gelap)
        context.setFillColor(trackColor.cgColor)
        let bgPath = CGPath(roundedRect: trackRect, cornerWidth: trackHeight / 2, cornerHeight: trackHeight / 2, transform: nil)
        context.addPath(bgPath)
        context.fillPath()
        
        // 2. Active Progress Track (Oranye hangat)
        let effectiveVal = isMuted ? 0.0 : CGFloat(max(0.0, min(1.0, value)))
        if effectiveVal > 0 {
            let activeWidth = max(0, trackWidth * effectiveVal)
            let activeRect = CGRect(x: knobRadius, y: trackY, width: activeWidth, height: trackHeight)
            let activePath = CGPath(roundedRect: activeRect, cornerWidth: trackHeight / 2, cornerHeight: trackHeight / 2, transform: nil)
            context.setFillColor(isMuted ? trackColor.cgColor : accentColor.cgColor)
            context.addPath(activePath)
            context.fillPath()
        }
        
        // 3. White Knob with Soft Shadow
        let knobX = knobRadius + (trackWidth * effectiveVal)
        let knobCenterY = bounds.height / 2
        let knobRect = CGRect(x: knobX - knobRadius, y: knobCenterY - knobRadius, width: knobRadius * 2, height: knobRadius * 2)
        
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 2.0, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: knobRect)
        context.restoreGState()
    }
    
    public override func mouseDown(with event: NSEvent) {
        isDragging = true
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
            onEditingChanged?(false)
        }
    }
    
    public override func scrollWheel(with event: NSEvent) {
        let delta = Float(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.003 : 0.03)
        let newValue = max(0.0, min(1.0, value + delta))
        if newValue != value {
            self.value = newValue
            onValueChanged?(newValue)
        }
    }
    
    private func updateValue(from event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let trackWidth = bounds.width - (knobRadius * 2)
        guard trackWidth > 0 else { return }
        let rawProgress = (location.x - knobRadius) / trackWidth
        let clamped = max(0.0, min(1.0, Float(rawProgress)))
        self.value = clamped
        onValueChanged?(clamped)
    }
}

#Preview {
    VStack(spacing: 20) {
        CustomSlider(value: .constant(0.65), isMuted: false)
        CustomSlider(value: .constant(0.30), isMuted: true)
        CustomSlider(value: .constant(1.0), isMuted: false, accentColor: Color.orange)
    }
    .padding()
    .frame(width: 250, height: 120)
    .background(Color(white: 0.15))
}
