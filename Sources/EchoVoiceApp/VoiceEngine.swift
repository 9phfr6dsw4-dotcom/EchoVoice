import EchoVoiceCore
import Foundation
import HuggingFace
import MLX
import MLXAudioCore
import MLXAudioTTS

/// Runs Breeze TTS 2, one recording part at a time.
actor VoiceEngine {
    enum EngineError: LocalizedError {
        case notLoaded, incompleteDownload, emptyAudio
        var errorDescription: String? {
            switch self {
            case .notLoaded: return "The voice model isn't loaded yet."
            case .incompleteDownload: return "The model download is incomplete. Download it again in Settings."
            case .emptyAudio: return "The voice model returned no audio. Try a different take."
            }
        }
    }
    struct PartResult: Sendable { let samples: [Float]; let steps: Int }
    nonisolated let modelsFolder: URL
    private var model: BreezeTTSModel?
    private var reference: MLXArray?
    private var referenceText = ""
    static let sampleRate = 24_000

    init(modelsFolder: URL) { self.modelsFolder = modelsFolder }

    nonisolated func folder(for repository: String) -> URL {
        modelsFolder.appendingPathComponent("mlx-audio")
            .appendingPathComponent(repository.replacingOccurrences(of: "/", with: "_"))
    }
    nonisolated private func hasFile(_ name: String, in folder: URL) -> Bool {
        let url = folder.appendingPathComponent(name)
        return ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) > 0
    }
    nonisolated private func hasWeights(in folder: URL) -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.contains { $0.pathExtension == "safetensors" && hasFile($0.lastPathComponent, in: folder) }
    }
    nonisolated func isDownloaded(_ selected: VoiceModel) -> Bool {
        let directory = folder(for: selected.repository)
        guard hasFile("config.json", in: directory), hasWeights(in: directory),
              hasFile("tokenizer_config.json", in: directory),
              hasFile("tokenizer.json", in: directory) ||
                (hasFile("vocab.json", in: directory) && hasFile("merges.txt", in: directory)) else { return false }
        let tokenizer = directory.appendingPathComponent("audio_tokenizer")
        return selected == .breeze && hasWeights(in: tokenizer) && hasFile("config.json", in: tokenizer)
    }

    /// Always snapshots all files, including subfolder weights. Resumes partial downloads.
    func download(_ selected: VoiceModel, progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> URL {
        guard selected == .breeze else { throw EngineError.notLoaded }
        if isDownloaded(selected) { return folder(for: selected.repository) }
        let client = HubClient(cache: nil)
        for (index, repository) in selected.repositories.enumerated() {
            try Task.checkCancellation()
            guard let repoID = Repo.ID(rawValue: repository) else { throw EngineError.incompleteDownload }
            let destination = folder(for: repository)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            do {
                _ = try await client.downloadSnapshot(
                    of: repoID, kind: .model, to: destination, revision: "main",
                    matching: ["*.safetensors", "*.json", "*.txt", "LICENSE*"],
                    progressHandler: { value in
                        progress((Double(index) + value.fractionCompleted) / Double(selected.repositories.count))
                    }
                )
            } catch let error as HubCacheError {
                // swift-huggingface 0.12 reports this after writing a cache-free snapshot.
                guard case .snapshotRequiresCacheOrDestination(_) = error else { throw error }
            }
        }
        try Task.checkCancellation()
        guard isDownloaded(selected) else { throw EngineError.incompleteDownload }
        return folder(for: selected.repository)
    }

    func prepare(_ selected: VoiceModel, progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        guard selected == .breeze else { throw EngineError.notLoaded }
        if model != nil { return }
        unload()
        let directory = try await download(selected, progress: progress)
        try Task.checkCancellation()
        model = try await BreezeTTSModel.fromModelDirectory(directory)
    }
    func isLoaded(_ selected: VoiceModel) -> Bool { selected == .breeze && model != nil }

    func setReference(_ samples: [Float], transcript: String) throws {
        guard model != nil else { throw EngineError.notLoaded }
        reference = MLXArray(samples)
        referenceText = transcript
    }

    func speak(text: String, direction: String?, seed: UInt64) async throws -> PartResult {
        guard let model, let reference else { throw EngineError.notLoaded }
        MLXRandom.seed(seed)
        Memory.cacheLimit = 512 * 1024 * 1024
        defer { Memory.clearCache() }
        var parameters = model.defaultGenerationParameters
        parameters.maxTokens = VoiceModel.breeze.maxStepsPerPart
        let stream = model.generateStream(text: text, voice: direction, refAudio: reference,
            refText: referenceText, language: "English", generationParameters: parameters)
        var samples: [Float] = []
        var steps = 0
        for try await event in stream {
            try Task.checkCancellation()
            switch event {
            case .token: steps += 1
            case .info(let info): steps = max(steps, info.generationTokenCount)
            case .audio(let audio): samples += audio.asArray(Float.self)
            case .progress: break
            }
        }
        guard !samples.isEmpty else { throw EngineError.emptyAudio }
        return PartResult(samples: samples, steps: steps)
    }
    func unload() {
        reference = nil; referenceText = ""; model = nil
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
