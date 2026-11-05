import Cocoa

let size = CGSize(width: 1024, height: 1024)
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: Int(size.width),
    height: Int(size.height),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Failed to create CGContext")
}

let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.current = nsContext

// 1. Draw Outer Drop Shadow for the squircle (Standard macOS Big Sur / Sonoma icon spec)
let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185.0
let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -24), blur: 36, color: NSColor(calibratedWhite: 0, alpha: 0.42).cgColor)
context.addPath(squirclePath)
context.setFillColor(NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.18, alpha: 1.0).cgColor)
context.fillPath()
context.restoreGState()

// 2. Draw Squircle Background Gradient
context.saveGState()
context.addPath(squirclePath)
context.clip()

// Deep space brushed dark slate gradient
let bgGradientColors = [
    NSColor(calibratedRed: 0.15, green: 0.17, blue: 0.24, alpha: 1.0).cgColor,
    NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.15, alpha: 1.0).cgColor,
    NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.10, alpha: 1.0).cgColor
] as CFArray
let bgLocations: [CGFloat] = [0.0, 0.65, 1.0]
if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgGradientColors, locations: bgLocations) {
    context.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: 512, y: 924),
        end: CGPoint(x: 512, y: 100),
        options: []
    )
}

// Top Rim Light (Soft metallic top bevel)
let topRimColors = [
    NSColor(calibratedWhite: 1.0, alpha: 0.22).cgColor,
    NSColor(calibratedWhite: 1.0, alpha: 0.0).cgColor
] as CFArray
if let rimGrad = CGGradient(colorsSpace: colorSpace, colors: topRimColors, locations: [0.0, 1.0]) {
    context.drawLinearGradient(rimGrad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 880), options: [])
}

// Background Sound Waves radiating from center speaker/core
let waveCenter = CGPoint(x: 512, y: 512)
context.saveGState()
for i in 1...5 {
    let r = CGFloat(i * 75)
    let wavePath = CGMutablePath()
    wavePath.addArc(center: waveCenter, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.addPath(wavePath)
    let alpha = CGFloat(0.04 - Double(i) * 0.006)
    context.setStrokeColor(NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: max(0.015, alpha)).cgColor)
    context.setLineWidth(2.0)
    context.strokePath()
}
context.restoreGState()

// 3. Notch Tick Marks for Faders (dB scales: +6, 0dB [center], -6, -12, -inf)
let faderXPositions: [CGFloat] = [325, 512, 699]
let faderValues: [CGFloat] = [0.65, 0.88, 0.50] // level positions

let trackWidth: CGFloat = 24.0
let trackHeight: CGFloat = 520.0
let trackBottomY: CGFloat = 252.0
let trackTopY = trackBottomY + trackHeight

context.saveGState()
for x in faderXPositions {
    // Draw tick marks on left and right of each slider
    let tickCount = 9
    for t in 0..<tickCount {
        let frac = CGFloat(t) / CGFloat(tickCount - 1)
        let ty = trackBottomY + trackHeight * frac
        let isMain = (t == 0 || t == 4 || t == tickCount - 1) // bottom, middle (0dB), top
        let tickW: CGFloat = isMain ? 12 : 7
        let alpha: CGFloat = isMain ? 0.35 : 0.18
        
        context.setFillColor(NSColor(calibratedWhite: 1.0, alpha: alpha).cgColor)
        // Left tick
        context.fill(CGRect(x: x - trackWidth/2 - tickW - 8, y: ty - 1, width: tickW, height: 2))
        // Right tick
        context.fill(CGRect(x: x + trackWidth/2 + 8, y: ty - 1, width: tickW, height: 2))
    }
}
context.restoreGState()

// 4. Draw 3 Vertical Mixer Sliders (Faders)
let activeGradients: [(top: NSColor, bottom: NSColor, glow: NSColor)] = [
    // Left: Electric Neon Cyan / Aqua
    (top: NSColor(calibratedRed: 0.0, green: 0.90, blue: 1.0, alpha: 1.0),
     bottom: NSColor(calibratedRed: 0.0, green: 0.45, blue: 0.95, alpha: 1.0),
     glow: NSColor(calibratedRed: 0.0, green: 0.75, blue: 1.0, alpha: 0.6)),
    
    // Center: Apple Signature Vibrant Amber / Orange / Flame
    (top: NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.20, alpha: 1.0),
     bottom: NSColor(calibratedRed: 1.0, green: 0.30, blue: 0.02, alpha: 1.0),
     glow: NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.05, alpha: 0.7)),
    
    // Right: Sunset Neon Purple / Magenta
    (top: NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.72, alpha: 1.0),
     bottom: NSColor(calibratedRed: 0.65, green: 0.15, blue: 0.90, alpha: 1.0),
     glow: NSColor(calibratedRed: 0.90, green: 0.25, blue: 0.80, alpha: 0.6))
]

for idx in 0..<3 {
    let x = faderXPositions[idx]
    let val = faderValues[idx]
    let col = activeGradients[idx]
    
    let trackRect = CGRect(x: x - trackWidth / 2, y: trackBottomY, width: trackWidth, height: trackHeight)
    let trackPath = CGPath(roundedRect: trackRect, cornerWidth: trackWidth / 2, cornerHeight: trackWidth / 2, transform: nil)
    
    // Dark Inset Track Well
    context.saveGState()
    context.addPath(trackPath)
    context.setFillColor(NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.07, alpha: 0.95).cgColor)
    context.fillPath()
    
    // Inset Track Border & Shadow
    context.addPath(trackPath)
    context.setStrokeColor(NSColor(calibratedWhite: 0, alpha: 0.7).cgColor)
    context.setLineWidth(2.0)
    context.strokePath()
    context.restoreGState()
    
    // Active Level Bar (Filled Progress)
    let activeHeight = trackHeight * val
    let activeRect = CGRect(x: x - trackWidth / 2, y: trackBottomY, width: trackWidth, height: activeHeight)
    let activePath = CGPath(roundedRect: activeRect, cornerWidth: trackWidth / 2, cornerHeight: trackWidth / 2, transform: nil)
    
    context.saveGState()
    // Soft glow around active track
    context.setShadow(offset: .zero, blur: 14, color: col.glow.cgColor)
    context.addPath(activePath)
    context.clip()
    
    let gradColors = [col.bottom.cgColor, col.top.cgColor] as CFArray
    if let grad = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: [0.0, 1.0]) {
        context.drawLinearGradient(
            grad,
            start: CGPoint(x: x, y: trackBottomY),
            end: CGPoint(x: x, y: trackBottomY + activeHeight),
            options: []
        )
    }
    context.restoreGState()
    
    // Fader Knob Position
    let knobY = trackBottomY + activeHeight
    
    // Knob Glow Aura
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 2), blur: 20, color: col.glow.cgColor)
    context.setFillColor(col.glow.withAlphaComponent(0.4).cgColor)
    context.fillEllipse(in: CGRect(x: x - 25, y: knobY - 25, width: 50, height: 50))
    context.restoreGState()
    
    // Fader Knob Body (3D Precision Machined Aluminum / Glass)
    let knobWidth: CGFloat = 92.0
    let knobHeight: CGFloat = 46.0
    let knobRect = CGRect(x: x - knobWidth / 2, y: knobY - knobHeight / 2, width: knobWidth, height: knobHeight)
    let knobCornerRadius: CGFloat = 12.0
    let knobPath = CGPath(roundedRect: knobRect, cornerWidth: knobCornerRadius, cornerHeight: knobCornerRadius, transform: nil)
    
    // Deep 3D Drop Shadow for Knob
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 16, color: NSColor(calibratedWhite: 0, alpha: 0.65).cgColor)
    context.addPath(knobPath)
    context.setFillColor(NSColor(calibratedWhite: 0.95, alpha: 1.0).cgColor)
    context.fillPath()
    context.restoreGState()
    
    // Metallic Finish Gradient on Knob
    context.saveGState()
    context.addPath(knobPath)
    context.clip()
    
    let metalGradColors = [
        NSColor(calibratedWhite: 0.82, alpha: 1.0).cgColor,
        NSColor(calibratedWhite: 0.98, alpha: 1.0).cgColor,
        NSColor(calibratedWhite: 0.78, alpha: 1.0).cgColor,
        NSColor(calibratedWhite: 0.68, alpha: 1.0).cgColor
    ] as CFArray
    let metalLocations: [CGFloat] = [0.0, 0.45, 0.55, 1.0]
    if let metalGrad = CGGradient(colorsSpace: colorSpace, colors: metalGradColors, locations: metalLocations) {
        context.drawLinearGradient(metalGrad, start: CGPoint(x: x, y: knobY + knobHeight / 2), end: CGPoint(x: x, y: knobY - knobHeight / 2), options: [])
    }
    
    // Knob Top Bevel Highlight Line
    let topBevelY = knobY + knobHeight / 2 - 2
    context.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.85).cgColor)
    context.fill(CGRect(x: x - knobWidth / 2 + 4, y: topBevelY, width: knobWidth - 8, height: 1.5))
    
    // Knob Center Indicator Slot (Glowing colored line)
    let slotWidth: CGFloat = 42.0
    let slotHeight: CGFloat = 4.0
    let slotRect = CGRect(x: x - slotWidth / 2, y: knobY - slotHeight / 2, width: slotWidth, height: slotHeight)
    let slotPath = CGPath(roundedRect: slotRect, cornerWidth: slotHeight / 2, cornerHeight: slotHeight / 2, transform: nil)
    
    // Slot Inset Dark Background
    context.setFillColor(NSColor(calibratedWhite: 0.15, alpha: 0.8).cgColor)
    context.addPath(slotPath)
    context.fillPath()
    
    // Glowing LED Line inside Slot
    context.setShadow(offset: .zero, blur: 6, color: col.top.cgColor)
    context.setFillColor(col.top.cgColor)
    let ledRect = slotRect.insetBy(dx: 1.5, dy: 0.5)
    let ledPath = CGPath(roundedRect: ledRect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
    context.addPath(ledPath)
    context.fillPath()
    
    context.restoreGState() // pop knob clipping
    
    // Crisp Knob Outline Stroke
    context.saveGState()
    context.addPath(knobPath)
    context.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.45).cgColor)
    context.setLineWidth(1.0)
    context.strokePath()
    context.restoreGState()
}

// 5. Header: Sleek, Illuminated Speaker Cone Symbol
context.saveGState()
let speakerConfig = NSImage.SymbolConfiguration(pointSize: 52, weight: .semibold)
    .applying(.init(paletteColors: [NSColor(calibratedWhite: 0.95, alpha: 0.9)]))

if let speakerSym = NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: nil)?.withSymbolConfiguration(speakerConfig) {
    let symSize = speakerSym.size
    let symRect = CGRect(x: (size.width - symSize.width) / 2, y: 812, width: symSize.width, height: symSize.height)
    
    // Soft ambient glow behind speaker symbol
    context.setShadow(offset: .zero, blur: 20, color: NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 0.5).cgColor)
    speakerSym.draw(in: symRect, from: .zero, operation: .sourceOver, fraction: 0.95)
}
context.restoreGState()

// Pop Squircle Clipping
context.restoreGState()

// 6. Squircle Border Inset Highlight (Apple Glass Bevel)
context.saveGState()
let strokePath = CGPath(roundedRect: squircleRect.insetBy(dx: 1.0, dy: 1.0), cornerWidth: cornerRadius - 1.0, cornerHeight: cornerRadius - 1.0, transform: nil)
context.addPath(strokePath)
context.setLineWidth(2.0)
context.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.18).cgColor)
context.strokePath()
context.restoreGState()

// Save output 1024x1024 PNG
guard let cgImage = context.makeImage() else {
    fatalError("Failed to make CGImage")
}

let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
bitmapRep.size = size
guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to create PNG data")
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let outputURL = URL(fileURLWithPath: outputPath)
try pngData.write(to: outputURL)
print("Successfully generated icon at \(outputPath)")
