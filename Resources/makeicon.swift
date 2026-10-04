// Draws AppIcon.iconset from an SF Symbol so the bundle isn't iconless in Finder.
// Renders straight into an NSBitmapImageRep: NSImage.lockFocus() has no usable
// backing store in a plain command-line process.
import AppKit

/// The exact set iconutil expects: each base at 1x and 2x.
let bases = [16, 32, 128, 256, 512]
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ size: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: size, pixelsHigh: size,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let side = CGFloat(size)
    let plate = NSRect(x: 0, y: 0, width: side, height: side).insetBy(dx: side * 0.06, dy: side * 0.06)
    let path = NSBezierPath(roundedRect: plate, xRadius: side * 0.22, yRadius: side * 0.22)
    NSGradient(colors: [NSColor(srgbRed: 0.24, green: 0.56, blue: 0.98, alpha: 1),
                        NSColor(srgbRed: 0.09, green: 0.26, blue: 0.70, alpha: 1)])?
        .draw(in: path, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: side * 0.44, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "powerplug.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: (side - s.width) / 2, y: (side - s.height) / 2,
                               width: s.width, height: s.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for base in bases {
    for (pixels, suffix) in [(base, ""), (base * 2, "@2x")] {
        guard let data = render(pixels) else {
            FileHandle.standardError.write(Data("failed to render \(pixels)px\n".utf8))
            exit(1)
        }
        try data.write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)\(suffix).png"))
    }
}
