import AppKit
import CoreText

// Reproducible Pearl Editorial artwork. No downloaded images or external fonts.
// The .icon background is supplied by Icon Composer; its foreground has full-size transparency.
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

// Quantized rows avoid gradient dithering noise and keep repository PNGs compact.
func paintGradient(_ context: CGContext, top: [Double], bottom: [Double]) {
    for y in 0..<size {
        let t = Double(y) / Double(size - 1)
        let rgb = zip(bottom, top).map { floor(($0 + ($1 - $0) * t) * 255) / 255 }
        context.setFillColor(CGColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1))
        context.fill(CGRect(x: 0, y: y, width: size, height: 1))
    }
}

func render(to url: URL, background: Bool) throws {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size * 4, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    if background {
        context.saveGState()
        context.addPath(CGPath(roundedRect: canvas, cornerWidth: 224, cornerHeight: 224, transform: nil))
        context.clip()
        paintGradient(context, top: [0.998, 0.990, 0.961], bottom: [0.878, 0.863, 0.808])
        context.restoreGState()
    }

    let font = CTFontCreateWithName("Baskerville-Italic" as CFString, 1, nil)
    var character: UniChar = 69 // E
    var glyph = CGGlyph()
    guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
          let original = CTFontCreatePathForGlyph(font, glyph, nil) else {
        throw NSError(domain: "PearlIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "The monogram could not be drawn."])
    }
    let bounds = original.boundingBoxOfPath
    let scale = 604 / bounds.height
    var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
        tx: (1024 - bounds.width * scale) / 2 - bounds.minX * scale,
        ty: (1024 - bounds.height * scale) / 2 - bounds.minY * scale)
    let monogram = original.copy(using: &transform)!
    if background {
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -7), blur: 14,
                          color: CGColor(srgbRed: 0.15, green: 0.25, blue: 0.23, alpha: 0.18))
        context.addPath(monogram)
        context.setFillColor(CGColor(srgbRed: 0.20, green: 0.35, blue: 0.35, alpha: 1))
        context.fillPath()
        context.restoreGState()
    }
    context.addPath(monogram)
    context.clip()
    paintGradient(context, top: [0.27, 0.43, 0.42], bottom: [0.14, 0.29, 0.29])

    let image = NSBitmapImageRep(cgImage: context.makeImage()!)
    guard let data = image.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PearlIcon", code: 2)
    }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

try render(to: root.appendingPathComponent("Resources/AppIcon.icon/Assets/monogram.png"), background: false)
try render(to: root.appendingPathComponent("Resources/AppIcon-1024.png"), background: true)
try FileManager.default.createDirectory(at: root.appendingPathComponent("docs/images"), withIntermediateDirectories: true)
let fallback = try Data(contentsOf: root.appendingPathComponent("Resources/AppIcon-1024.png"))
try fallback.write(to: root.appendingPathComponent("docs/images/echovoice-icon.png"))
print("Pearl Editorial icon artwork generated.")
