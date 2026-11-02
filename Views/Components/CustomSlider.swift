import SwiftUI
import AppKit

/// Slider kustom dengan estetika macOS persis seperti screenshot (SoundSource style).
/// Mendukung rentang volume hingga 200% (2.0) dengan titik dasar 100% (1.0) di tengah,
/// dilengkapi tick notch pada 100%, magnet snap, dan double-click reset ke 100%.
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
        accentColor: Color = Color(red: 1.0, green: 0.584, blue: 0.0), // Oranye hangat
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

/// Custom NSView yang menangani rendering dan event mouse langsung di tingkat AppKit.
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
    
    public var accentColor: NSColor = NSColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0) {
        didSet { needsDisplay = true }
    }
    
    public var boostColor: NSColor = NSColor(red: 1.0, green: 0.75, blue: 0.2, alpha: 1.0) {
        didSet { needsDisplay = true }
    }
    
    public var trackColor: NSColor = NSColor(white: 0.32, alpha: 1.0)
    public var onValueChanged: ((Float) -> Void)?
    public var onEditingChanged: ((Bool) -> Void)?
    
    private let knobRadius: CGFloat = 6.0
    private let trackHeight: CGFloat = 3.0
    private var isDragging: Bool = false
    public var isCurrentlyDragging: Bool { isDragging }
    
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
        
        // 2. Baseline Tick Notch pada 100% (Unity Gain di tengah)
        let baselineNorm = CGFloat(baselineValue / maxValue)
        let tickX = knobRadius + (trackWidth * baselineNorm)
        let tickRect = CGRect(x: tickX - 0.75, y: trackY - 2.0, width: 1.5, height: trackHeight + 4.0)
        context.setFillColor(NSColor(white: 0.55, alpha: 0.9).cgColor)
        context.fill(tickRect)
        
        // 3. Active Progress Track
        let progress = CGFloat(max(0.0, min(maxValue, value)) / maxValue)
        let effectiveProgress = isMuted ? 0.0 : progress
        
        if effectiveProgress > 0 {
            let activeWidth = max(0, trackWidth * effectiveProgress)
            let activeRect = CGRect(x: knobRadius, y: trackY, width: activeWidth, height: trackHeight)
            let activePath = CGPath(roundedRect: activeRect, cornerWidth: trackHeight / 2, cornerHeight: trackHeight / 2, transform: nil)
            
            // Jika volume melebihi 100%, gunakan warna oranye-emas terang untuk zona boost
            let fillColor = isMuted ? trackColor : (value > baselineValue ? boostColor : accentColor)
            context.setFillColor(fillColor.cgColor)
            context.addPath(activePath)
            context.fillPath()
        }
        
        // 4. White Knob with Soft Drop Shadow
        let knobX = knobRadius + (trackWidth * effectiveProgress)
        let knobCenterY = bounds.height / 2
        let knobRect = CGRect(x: knobX - knobRadius, y: knobCenterY - knobRadius, width: knobRadius * 2, height: knobRadius * 2)
        
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 2.5, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: knobRect)
        context.restoreGState()
    }
    
    public override func mouseDown(with event: NSEvent) {
        // Double click: Reset kembali ke baseline (100% / 1.0)
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
        
        // Magnet Snap ke 100% (baselineValue) jika berada di radius +/- 5%
        if abs(calcVal - baselineValue) < 0.06 {
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
