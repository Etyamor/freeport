// Generates the website's icon, favicon and Open Graph card.
// Run: swift Resources/makeweb.swift docs
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs"

func canvas(_ width: Int, _ height: Int, _ draw: (CGFloat, CGFloat) -> Void) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: width, pixelsHigh: height,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw(CGFloat(width), CGFloat(height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let blue = NSColor(srgbRed: 0.24, green: 0.56, blue: 0.98, alpha: 1)
let deepBlue = NSColor(srgbRed: 0.09, green: 0.26, blue: 0.70, alpha: 1)

func drawPlate(_ side: CGFloat, at origin: NSPoint = .zero) {
    let plate = NSRect(x: origin.x, y: origin.y, width: side, height: side).insetBy(dx: side * 0.06, dy: side * 0.06)
    let path = NSBezierPath(roundedRect: plate, xRadius: side * 0.22, yRadius: side * 0.22)
    NSGradient(colors: [blue, deepBlue])?.draw(in: path, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: side * 0.44, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "powerplug.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: origin.x + (side - s.width) / 2,
                               y: origin.y + (side - s.height) / 2,
                               width: s.width, height: s.height))
    }
}

// App icon and favicon
for (size, name) in [(512, "icon.png"), (180, "apple-touch-icon.png"), (64, "favicon.png")] {
    if let data = canvas(size, size, { side, _ in drawPlate(side) }) {
        try data.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    }
}

// Open Graph / Twitter card
if let card = canvas(1200, 630, { w, h in
    NSGradient(colors: [NSColor(srgbRed: 0.05, green: 0.07, blue: 0.12, alpha: 1),
                        NSColor(srgbRed: 0.02, green: 0.03, blue: 0.06, alpha: 1)])?
        .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)

    drawPlate(190, at: NSPoint(x: 90, y: h - 290))

    func text(_ string: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, y: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ]
        NSAttributedString(string: string, attributes: attrs)
            .draw(in: NSRect(x: 92, y: y, width: w - 180, height: size * 1.6))
    }

    text("FreePort", 86, .bold, .white, y: h - 400)
    text("See which app is using which port on macOS", 40, .medium,
         NSColor(srgbRed: 0.72, green: 0.78, blue: 0.9, alpha: 1), y: h - 470)
    text("Docker · OrbStack · DDEV · Node · Bun — free any port in one click", 29, .regular,
         NSColor(srgbRed: 0.45, green: 0.53, blue: 0.68, alpha: 1), y: h - 530)
    text("Free and open source · github.com/Etyamor/freeport", 24, .regular,
         NSColor(srgbRed: 0.35, green: 0.45, blue: 0.62, alpha: 1), y: 54)
}) {
    try card.write(to: URL(fileURLWithPath: "\(out)/og.png"))
}

print("wrote assets to \(out)/")
