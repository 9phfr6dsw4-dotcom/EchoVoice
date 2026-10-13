import EchoVoiceCore
import Foundation
import HuggingFace
import MLX
import MLXAudioCore
import MLXAudioTTS

/// Runs Breeze TTS 2 on this Mac. The model is downloaded once, loaded when needed, and released
/// to free memory when EchoVoice has been idle for a while. One recording part at a time.
actor VoiceEngine {
    enum EngineError: LocalizedError {
        case notLoaded
        case badRepository(String)
        case emptyAudio

        var errorDescription: String? {
            switch self {
            case .notLoaded: return "The voice model isn't loaded yet."
            case .badRepository(let name): return "Unknown model download: \(name)"
            case .emptyAudio: return "The voice model returned no audio for this part. Try again, or try a different take."
            }
        }
    }

    struct PartResult: Sendable {
        let samples: [Float]
        let steps: Int
    }

    let modelsFolder: URL
    private var model: BreezeTTSModel?
    private(set) var loadedQuality: ModelQuality?

    init(modelsFolder: URL) {
        self.modelsFolder = modelsFolder
    }

    /// Breeze speaks at 24 kHz.
    static let sampleRate = 24_000

    /// Where a quality's files live once downloaded (the layout mlx-audio uses).
    nonisolated func folder(for quality: ModelQuality) -> URL {
        modelsFolder
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(quality.repository.replacingOccurrences(of: "/", with: "_"))
    }

    nonisolated func isDownloaded(_ quality: ModelQuality) -> Bool {
        let folder = folder(for: quality)
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("config.json").path),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else {
            return false
        }
        return files.contains { file in
            file.pathExtension == "safetensors" && ((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) > 0
        }
    }

    /// Downloads a quality if it isn't on this Mac yet. `progress` gets 0…1.
    func download(_ quality: ModelQuality, progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> URL {
        guard let repoID = Repo.ID(rawValue: quality.repository) else { throw EngineError.badRepository(quality.repository) }
        try FileManager.default.createDirectory(at: modelsFolder, withIntermediateDirectories: true)
        let cache = HubCache(cacheDirectory: modelsFolder)
        // No second copy in a shared cache: the files are kept only in EchoVoice's own folder.
        let client = HubClient(cache: nil)
        do {
            return try await ModelUtils.resolveOrDownloadModel(
                client: client,
                cache: cache,
                repoID: repoID,
                requiredExtension: "safetensors",
                progressHandler: { value in progress(value.fractionCompleted) }
            )
        } catch let error as HubCacheError {
            // Without a shared cache, swift-huggingface 0.12 writes every file into EchoVoice's
            // folder and then reports that no cache was configured. The download is complete.
            guard case .snapshotRequiresCacheOrDestination(_) = error, isDownloaded(quality) else { throw error }
            return folder(for: quality)
        }
    }

    /// Makes sure the chosen quality is downloaded and loaded.
    func prepare(_ quality: ModelQuality, progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        if model != nil, loadedQuality == quality { return }
        unload()
        let folder = try await download(quality, progress: progress)
        try Task.checkCancellation()
        model = try await BreezeTTSModel.fromModelDirectory(folder)
        loadedQuality = quality
    }

    var isLoaded: Bool { model != nil }

    /// Speaks one part of a script in the reference voice. `direction` is the optional delivery
    /// instruction ("warm and slow").
    func speak(text: String, direction: String?, reference: [Float], referenceText: String, seed: UInt64) async throws -> PartResult {
        guard let model else { throw EngineError.notLoaded }
        MLXRandom.seed(seed)
        Memory.cacheLimit = 512 * 1024 * 1024
        defer { Memory.clearCache() }
        let instruction = direction.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        var samples: [Float] = []
        var steps = 0
        let stream = model.generateStream(
            text: text,
            voice: instruction,
            refAudio: MLXArray(reference),
            refText: referenceText,
            language: "English",
            generationParameters: model.defaultGenerationParameters
        )
        for try await event in stream {
            try Task.checkCancellation()
            switch event {
            case .token:
                steps += 1
            case .info(let info):
                steps = max(steps, info.generationTokenCount)
            case .audio(let audio):
                samples += audio.asArray(Float.self)
            case .progress:
                break
            }
        }
        guard !samples.isEmpty else { throw EngineError.emptyAudio }
        return PartResult(samples: samples, steps: steps)
    }

    /// Releases the model and its memory. It loads again on the next recording.
    func unload() {
        model = nil
        loadedQuality = nil
        Memory.clearCache()
    }
}

/// Reads any audio file macOS understands as mono samples at `sampleRate`.
enum AudioFileReader {
    static func monoSamples(from url: URL, sampleRate: Int) throws -> [Float] {
        let (_, audio) = try loadAudioArray(from: url, sampleRate: sampleRate)
        return audio.asArray(Float.self)
    }
}

/// `EchoVoice --mlx-self-test`: loads MLX's GPU library from inside the app and does a tiny
/// calculation. Used by the launch test to catch a broken package.
enum MLXSelfTest {
    static func runAndExit() -> Never {
        let doubled = MLXArray([1, 2, 3] as [Float]) * 2
        eval(doubled)
        let result = doubled.asArray(Float.self)
        if result == [2, 4, 6] {
            print("MLX self-test passed: the GPU library loaded and computed \(result).")
            exit(0)
        }
        print("MLX self-test failed: expected [2.0, 4.0, 6.0], got \(result).")
        exit(1)
    }
}
