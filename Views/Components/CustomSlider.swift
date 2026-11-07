import SwiftUI
import AppKit

/// Slider kustom dengan estetika macOS Sonoma & Sequoia persis seperti Control Center & SoundSource.
/// Mendukung rentang volume hingga 200% (2.0) dengan titik dasar 100% (1.0) di tengah,
/// dilengkapi notch unity gain pada 100%, magnet snap, double-click reset ke 100%, dan scroll wheel.
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

/// Custom NSView yang menangani rendering dan event mouse langsung di tingkat AppKit dengan kualitas Apple-native.
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
    
    public var boostColor: NSColor = NSColor(red: 1.0, green: 0.62, blue: 0.12, alpha: 1.0) {
        didSet { needsDisplay = true }
    }
    
    public var trackColor: NSColor = NSColor(white: 0.28, alpha: 0.50)
    public var onValueChanged: ((Float) -> Void)?
    public var onEditingChanged: ((Bool) -> Void)?
    
    private let knobRadius: CGFloat = 6.5
    private let trackHeight: CGFloat = 4.5
    private var isDragging: Bool = false
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
    
    public override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let trackWidth = bounds.width - (knobRadius * 2)
        let trackY = (bounds.height - trackHeight) / 2
        let trackRect = CGRect(x: knobRadius, y: trackY, width: max(0, trackWidth), height: trackHeight)
        
        // 1. Background Groove Track
        context.setFillColor(trackColor.cgColor)
        let bgPath = CGPath(roundedRect: trackRect, cornerWidth: trackHeight / 2, cornerHeight: trackHeight / 2, transform: nil)
        context.addPath(bgPath)
        context.fillPath()
        
        // Subtle inner stroke rim
        context.saveGState()
        context.addPath(bgPath)
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.08).cgColor)
        context.setLineWidth(0.6)
        context.strokePath()
        context.restoreGState()
        
        // 2. Baseline Unity Notch pada 100% (1.0)
        let baselineNorm = CGFloat(baselineValue / maxValue)
        let tickX = knobRadius + (trackWidth * baselineNorm)
        let tickHeight = trackHeight + 3.0
        let tickY = (bounds.height - tickHeight) / 2
        let tickRect = CGRect(x: tickX - 0.75, y: tickY, width: 1.5, height: tickHeight)
        let tickPath = CGPath(roundedRect: tickRect, cornerWidth: 0.75, cornerHeight: 0.75, transform: nil)
        context.setFillColor(NSColor(white: 1.0, alpha: 0.35).cgColor)
        context.addPath(tickPath)
        context.fillPath()
        
        // 3. Active Progress Track
        let progress = CGFloat(max(0.0, min(maxValue, value)) / maxValue)
        let effectiveProgress = isMuted ? 0.0 : progress
        
        if effectiveProgress > 0 {
            let activeWidth = max(0, trackWidth * effectiveProgress)
            let activeRect = CGRect(x: knobRadius, y: trackY, width: activeWidth, height: trackHeight)
            let activePath = CGPath(roundedRect: activeRect, cornerWidth: trackHeight / 2, cornerHeight: trackHeight / 2, transform: nil)
            
            let fillColor = isMuted ? trackColor : (value > baselineValue ? boostColor : accentColor)
            context.setFillColor(fillColor.cgColor)
            context.addPath(activePath)
            context.fillPath()
        }
        
        // 4. Apple-style White Knob with Soft Drop Shadow & Specular Rim
        let knobX = knobRadius + (trackWidth * effectiveProgress)
        let knobCenterY = bounds.height / 2
        let knobDiameter = knobRadius * 2
        let knobRect = CGRect(x: knobX - knobRadius, y: knobCenterY - knobRadius, width: knobDiameter, height: knobDiameter)
        
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1.0), blur: 2.5, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: knobRect)
        context.restoreGState()
        
        context.saveGState()
        context.setStrokeColor(NSColor(white: 0.0, alpha: 0.14).cgColor)
        context.setLineWidth(0.5)
        context.strokeEllipse(in: knobRect)
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
        let delta = Float(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.005 : 0.05)
        let newValue = max(0.0, min(maxValue, value + delta))
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
