import AppKit
import EchoVoiceCore
import SwiftUI

/// Native UI captures from the packaged app, with fictional fixtures in a temporary library.
/// This entry point refuses to run outside GitHub Actions and never uses the normal library.
@MainActor
enum CIReviewCapture {
    static func runAndExit() -> Never {
        guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
              let temporary = ProcessInfo.processInfo.environment["RUNNER_TEMP"] else {
            fputs("Design captures are available only on the GitHub Actions runner.\n", stderr)
            exit(64)
        }
        do {
            try capture(in: URL(fileURLWithPath: temporary, isDirectory: true))
            print("Native design captures passed: four screens at standard and minimum window sizes.")
            exit(0)
        } catch {
            fputs("Design capture failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func capture(in temporary: URL) throws {
        let fm = FileManager.default
        let fixture = temporary.appendingPathComponent("EchoVoice-review-\(UUID().uuidString)", isDirectory: true)
        let output = temporary.appendingPathComponent("EchoVoice-design-captures", isDirectory: true)
        let suite = "EchoVoice.CIReview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? fm.removeItem(at: fixture)
        }
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        let voice = Voice(name: "Ada", transcript: "Some stories deserve to be heard. The quiet moments. The unexpected turns.", seconds: 18)
        let second = Voice(name: "Milo", transcript: "A new idea begins with a simple question. What could we make together?", seconds: 21)
        let voices = fixture.appendingPathComponent("Voices", isDirectory: true)
        try fm.createDirectory(at: voices, withIntermediateDirectories: true)
        let samples = (0..<24_000).map { Float(sin(Double($0) * 2 * .pi * 220 / 24_000) * 0.15) }
        for item in [voice, second] {
            try WAVFile.write(samples: samples, sampleRate: 24_000, to: voices.appendingPathComponent(item.clipFileName))
        }
        let audio = fixture.appendingPathComponent("The quiet moments.wav")
        try WAVFile.write(samples: samples, sampleRate: 24_000, to: audio)
        let script = "Some stories deserve to be heard.\n\nThe quiet moments. The unexpected turns. The words that stay with us long after the room falls silent."
        let take = HistoryItem(voiceID: voice.id, voiceName: voice.name, script: script,
                               direction: "conversational", filePath: audio.path, seconds: 18, seed: 42,
                               quality: .standard, cutOffParts: [], generationSeconds: 24)
        let store = LibraryStore(fileURL: fixture.appendingPathComponent("library.json"))
        try store.save(LibraryState(voices: [voice, second], history: [take]))
        let originalLibrary = try Data(contentsOf: store.fileURL)
        defaults.set(script, forKey: AppModel.Keys.script)
        defaults.set("conversational", forKey: AppModel.Keys.direction)
        defaults.set(voice.id.uuidString, forKey: AppModel.Keys.voice)
        defaults.set(fixture.path, forKey: AppModel.Keys.outputFolder)
        let model = AppModel(defaults: defaults, supportRoot: fixture)
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()

        for (name, size) in [("standard", CGSize(width: 1180, height: 840)),
                             ("minimum", CGSize(width: 900, height: 620))] {
            for section in AppSection.allCases {
                model.section = section
                try render(RootView().environment(model), size: size,
                           to: output.appendingPathComponent("\(section.rawValue)-\(name).png"))
            }
        }
        // Also exercise the first-launch state against an empty, isolated library.
        let empty = AppModel(defaults: defaults, supportRoot: fixture.appendingPathComponent("Empty"))
        try render(RootView().environment(empty), size: CGSize(width: 900, height: 620),
                   to: output.appendingPathComponent("first-launch.png"))
        // The generated library must survive viewing every page byte-for-byte.
        guard try Data(contentsOf: store.fileURL) == originalLibrary else {
            throw CaptureError(message: "Viewing the redesigned screens changed saved library data.")
        }
    }

    private static func render<V: View>(_ content: V, size: CGSize, to url: URL) throws {
        let rect = CGRect(origin: .zero, size: size)
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = rect
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CaptureError(message: "Could not allocate a bitmap for \(url.lastPathComponent).")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]), png.count > 10_000 else {
            throw CaptureError(message: "The \(url.lastPathComponent) capture is empty.")
        }
        try png.write(to: url)
        window.orderOut(nil)
        window.contentView = nil
    }

    private struct CaptureError: Error {
        let message: String
    }
}
