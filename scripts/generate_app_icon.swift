import AppKit

func createIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    
    // Scale everything relative to 1024x1024 base coordinate space
    let s = size / 1024.0
    
    // Standard macOS squircle icon metrics on 1024x1024:
    // Centered squircle is 824x824, origin at (100, 100)
    let bodyRect = CGRect(x: 100 * s, y: 104 * s, width: 824 * s, height: 824 * s)
    let cornerRadius = 185.0 * s
    
    let squirclePath = CGPath(roundedRect: bodyRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    // 1. Drop shadow beneath squircle
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -22 * s),
        blur: 36 * s,
        color: NSColor(white: 0.0, alpha: 0.26).cgColor
    )
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor(white: 0.94, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // Secondary softer contact shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -8 * s),
        blur: 14 * s,
        color: NSColor(white: 0.0, alpha: 0.16).cgColor
    )
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor(white: 0.94, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 2. Body Gradient (Pristine Apple off-white satin paper finish)
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        NSColor(red: 0.99, green: 0.99, blue: 0.99, alpha: 1.0).cgColor,
        NSColor(red: 0.96, green: 0.96, blue: 0.95, alpha: 1.0).cgColor,
        NSColor(red: 0.92, green: 0.92, blue: 0.91, alpha: 1.0).cgColor
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.7, 1.0]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: locations) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 512 * s, y: 928 * s),
            end: CGPoint(x: 512 * s, y: 104 * s),
            options: []
        )
    }
    
    // Subtle top-down inner sheen
    let sheenColors = [
        NSColor(white: 1.0, alpha: 0.65).cgColor,
        NSColor(white: 1.0, alpha: 0.0).cgColor
    ] as CFArray
    if let sheenGrad = CGGradient(colorsSpace: colorSpace, colors: sheenColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            sheenGrad,
            start: CGPoint(x: 512 * s, y: 928 * s),
            end: CGPoint(x: 512 * s, y: 700 * s),
            options: []
        )
    }
    
    ctx.restoreGState()
    
    // 3. Subtle hairline edge border
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setStrokeColor(NSColor(white: 0.0, alpha: 0.09).cgColor)
    ctx.setLineWidth(1.5 * s)
    ctx.strokePath()
    ctx.restoreGState()
    
    // 4. Notepad Ruling Lines (Super Minimalistic)
    // 3 horizontal rules evenly positioned across the paper
    let lineXStart: CGFloat = 240 * s
    let lineXEnd: CGFloat = 784 * s
    let ruleYPositions: [CGFloat] = [640 * s, 500 * s, 360 * s]
    let ruleColor = NSColor(red: 0.78, green: 0.79, blue: 0.80, alpha: 0.75).cgColor
    
    ctx.saveGState()
    ctx.setStrokeColor(ruleColor)
    ctx.setLineWidth(6.0 * s)
    ctx.setLineCap(.round)
    
    for y in ruleYPositions {
        ctx.beginPath()
        ctx.move(to: CGPoint(x: lineXStart, y: y))
        ctx.addLine(to: CGPoint(x: lineXEnd, y: y))
        ctx.strokePath()
    }
    ctx.restoreGState()
    
    // 5. Obsidian Text Insertion Caret / Cursor
    // Positioned at the beginning of the first line
    let caretX: CGFloat = 280 * s
    let caretYCenter: CGFloat = 640 * s
    let caretHeight: CGFloat = 90 * s
    let caretWidth: CGFloat = 10.0 * s
    
    let caretRect = CGRect(
        x: caretX - caretWidth / 2,
        y: caretYCenter - caretHeight / 2,
        width: caretWidth,
        height: caretHeight
    )
    let caretPath = CGPath(roundedRect: caretRect, cornerWidth: caretWidth / 2, cornerHeight: caretWidth / 2, transform: nil)
    
    ctx.saveGState()
    ctx.addPath(caretPath)
    ctx.setFillColor(NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 0.95).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    image.unlockFocus()
    return image
}

func savePNG(image: NSImage, path: String, pixels: Int) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: pixels * 4,
        bitsPerPixel: 32
    ) else {
        fatalError("Failed to create bitmap rep")
    }
    
    rep.size = NSSize(width: pixels, height: pixels)
    
    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError() }
    NSGraphicsContext.current = ctx
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed")
    }
    try! pngData.write(to: URL(fileURLWithPath: path))
    print("Wrote: \(path) (\(pixels)x\(pixels))")
}

let icon = createIcon(size: 1024)
let iconsetDir = "Resources/MinimalNotepad.iconset"

let targets: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in targets {
    savePNG(image: icon, path: "\(iconsetDir)/\(name)", pixels: px)
}

print("All iconset PNGs generated successfully.")
