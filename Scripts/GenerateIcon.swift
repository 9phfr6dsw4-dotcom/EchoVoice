import Foundation

struct IconGenerationError: Error, CustomStringConvertible {
    let description: String
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else {
    fputs("usage: GenerateIcon.swift OUTPUT.iconset SOURCE-1024.png\n", stderr)
    exit(64)
}

let output = URL(fileURLWithPath: arguments[0], isDirectory: true)
let source = URL(fileURLWithPath: arguments[1])
let fileManager = FileManager.default
let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

func pngDimensions(_ url: URL) throws -> (UInt32, UInt32) {
    let data = try Data(contentsOf: url)
    let bytes = Array(data.prefix(24))
    guard bytes.count == 24,
          Array(bytes[0..<8]) == pngSignature,
          Array(bytes[12..<16]) == [73, 72, 68, 82] else {
        throw IconGenerationError(description: "Not a readable PNG: \(url.path)")
    }
    let width = UInt32(bytes[16]) << 24 | UInt32(bytes[17]) << 16 | UInt32(bytes[18]) << 8 | UInt32(bytes[19])
    let height = UInt32(bytes[20]) << 24 | UInt32(bytes[21]) << 16 | UInt32(bytes[22]) << 8 | UInt32(bytes[23])
    return (width, height)
}

func makeIconset() throws {
    let sourceSize = try pngDimensions(source)
    guard sourceSize.0 == 1024 && sourceSize.1 == 1024 else {
        throw IconGenerationError(description: "Source icon must be 1024x1024, got \(sourceSize.0)x\(sourceSize.1)")
    }
    try fileManager.createDirectory(at: output, withIntermediateDirectories: true)

    let sizes: [(String, Int)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
    ]

    for (name, size) in sizes {
        let destination = output.appendingPathComponent(name)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        if size == 1024 {
            // Retain the supplied source unchanged in the 512px @2x slot.
            try fileManager.copyItem(at: source, to: destination)
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            process.arguments = ["-s", "format", "png", "-z", "\(size)", "\(size)", source.path, "--out", destination.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw IconGenerationError(description: "sips failed while rendering \(name)")
            }
        }
        let resultSize = try pngDimensions(destination)
        guard resultSize.0 == size && resultSize.1 == size else {
            throw IconGenerationError(description: "Generated \(name) has unexpected dimensions \(resultSize.0)x\(resultSize.1)")
        }
    }
}

do {
    try makeIconset()
} catch {
    fputs("Icon generation failed: \(error)\n", stderr)
    exit(1)
}
