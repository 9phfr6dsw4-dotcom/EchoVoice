import AVFoundation
import Foundation
import Observation
import Speech

/// Records a voice clip from the Mac's microphone into a temporary file.
@MainActor
@Observable
final class ClipRecorder {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// 0…1, for the level meter.
    private(set) var level: Double = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private(set) var fileURL: URL?

    static let maximumSeconds: TimeInterval = 60

    enum RecorderError: LocalizedError {
        case noPermission
        case couldNotStart

        var errorDescription: String? {
            switch self {
            case .noPermission:
                return "EchoVoice doesn't have access to the microphone. Turn it on in System Settings → Privacy & Security → Microphone, then try again."
            case .couldNotStart:
                return "The microphone couldn't start. Check that a microphone is connected and selected in System Settings → Sound."
            }
        }
    }

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw RecorderError.noPermission }
        stop()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EchoVoice-clip-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record(forDuration: Self.maximumSeconds) else { throw RecorderError.couldNotStart }
        self.recorder = recorder
        fileURL = url
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let recorder else { return }
        if !recorder.isRecording {
            stop()
            return
        }
        recorder.updateMeters()
        let power = Double(recorder.averagePower(forChannel: 0))
        level = max(0, min(1, (power + 50) / 50))
        elapsed = recorder.currentTime
    }

    /// Stops recording; the clip stays at `fileURL`.
    func stop() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        level = 0
    }
}

/// Plays one sound file at a time: a finished recording or a voice clip.
@MainActor
@Observable
final class Playback: NSObject, AVAudioPlayerDelegate {
    private(set) var currentURL: URL?
    private(set) var isPlaying = false
    private(set) var progress: Double = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?

    func toggle(_ url: URL) {
        if currentURL == url, let player {
            if player.isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
            return
        }
        play(url)
    }

    func play(_ url: URL) {
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        player.play()
        self.player = player
        currentURL = url
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func isPlaying(_ url: URL) -> Bool {
        isPlaying && currentURL == url
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        currentURL = nil
        isPlaying = false
        progress = 0
    }

    private func tick() {
        guard let player, player.duration > 0 else { return }
        progress = player.currentTime / player.duration
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}

/// Writes down what's said in a voice clip with Apple's on-device speech recognition, so the
/// transcript Breeze needs doesn't have to be typed by hand.
enum ClipTranscriber {
    enum TranscriberError: LocalizedError {
        case unsupported
        case nothingHeard

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return "Apple's speech recognition isn't available for this language on this Mac. Type the words instead."
            case .nothingHeard:
                return "No words were recognized in this clip. Type them instead, or record again."
            }
        }
    }

    static func transcribe(_ url: URL, locale requested: Locale = Locale(identifier: "en-US")) async throws -> String {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw TranscriberError.unsupported
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task.detached(priority: .userInitiated) { () throws -> String in
            var text = ""
            for try await result in transcriber.results {
                text += " " + String(result.text.characters)
            }
            return text
        }
        do {
            let file = try AVAudioFile(forReading: url)
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            await analyzer.cancelAndFinishNow()
            collector.cancel()
            throw error
        }
        let text = try await collector.value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty else { throw TranscriberError.nothingHeard }
        return text
    }
}
