import AppKit
import EchoVoiceCore
import Foundation
import Observation

enum AppSection: String, CaseIterable, Identifiable {
    case generate, voices, recordings, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generate: return "Generate"
        case .voices: return "Voices"
        case .recordings: return "Recordings"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .generate: return "waveform"
        case .voices: return "person.wave.2"
        case .recordings: return "tray.full"
        case .settings: return "gearshape"
        }
    }

    var shortcut: Character {
        switch self {
        case .generate: return "1"
        case .voices: return "2"
        case .recordings: return "3"
        case .settings: return "4"
        }
    }
}

/// Where the voice model is.
enum ModelState: Equatable {
    case notDownloaded
    case downloading(Double)
    case loading
    case ready
    case idle
}

/// A recording being made right now.
struct GenerationProgress: Equatable {
    var part: Int
    var parts: Int
    var secondsLeft: Double?
    var stage: String
}

@MainActor
@Observable
final class AppModel {
    var section: AppSection = .generate
    var statusMessage: String?
    var errorMessage: String?

    private(set) var library = LibraryState()
    private(set) var modelState: ModelState = .notDownloaded
    private(set) var progress: GenerationProgress?
    private(set) var lastRecording: HistoryItem?

    // The Generate page, kept between launches.
    var script: String {
        get { storedScript }
        set { storedScript = newValue; defaults.set(newValue, forKey: Keys.script) }
    }
    var direction: String {
        get { storedDirection }
        set { storedDirection = newValue; defaults.set(newValue, forKey: Keys.direction) }
    }
    var selectedVoiceID: UUID? {
        get { storedVoiceID }
        set { storedVoiceID = newValue; defaults.set(newValue?.uuidString, forKey: Keys.voice) }
    }

    // Settings.
    var quality: ModelQuality {
        get { storedQuality }
        set {
            storedQuality = newValue
            defaults.set(newValue.rawValue, forKey: Keys.quality)
            refreshModelState()
        }
    }
    var playWhenDone: Bool {
        get { storedPlayWhenDone }
        set { storedPlayWhenDone = newValue; defaults.set(newValue, forKey: Keys.playWhenDone) }
    }
    /// Minutes of inactivity before the model's memory is released; 0 means never.
    var unloadAfterMinutes: Int {
        get { storedUnloadMinutes }
        set { storedUnloadMinutes = newValue; defaults.set(newValue, forKey: Keys.unloadMinutes); scheduleUnload() }
    }
    private(set) var outputFolder: URL

    let playback = Playback()

    private var storedScript: String
    private var storedDirection: String
    private var storedVoiceID: UUID?
    private var storedQuality: ModelQuality
    private var storedPlayWhenDone: Bool
    private var storedUnloadMinutes: Int

    enum Keys {
        static let script = "EchoVoice.script"
        static let direction = "EchoVoice.direction"
        static let voice = "EchoVoice.voice"
        static let quality = "EchoVoice.quality"
        static let playWhenDone = "EchoVoice.playWhenDone"
        static let unloadMinutes = "EchoVoice.unloadMinutes"
        static let outputFolder = "EchoVoice.outputFolder"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored let voicesFolder: URL
    @ObservationIgnored let engine: VoiceEngine
    private var generationTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var unloadTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let root = support.appendingPathComponent("EchoVoice", isDirectory: true)
        store = LibraryStore(fileURL: root.appendingPathComponent("library.json"))
        voicesFolder = root.appendingPathComponent("Voices", isDirectory: true)
        engine = VoiceEngine(modelsFolder: root.appendingPathComponent("Models", isDirectory: true))

        storedScript = defaults.string(forKey: Keys.script) ?? ""
        storedDirection = defaults.string(forKey: Keys.direction) ?? ""
        storedVoiceID = defaults.string(forKey: Keys.voice).flatMap(UUID.init(uuidString:))
        storedQuality = defaults.string(forKey: Keys.quality).flatMap(ModelQuality.init(rawValue:)) ?? .standard
        storedPlayWhenDone = defaults.object(forKey: Keys.playWhenDone) as? Bool ?? true
        storedUnloadMinutes = defaults.object(forKey: Keys.unloadMinutes) as? Int ?? 10
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        outputFolder = defaults.string(forKey: Keys.outputFolder).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? downloads.appendingPathComponent("EchoVoice", isDirectory: true)

        library = store.load()
        if selectedVoice == nil { storedVoiceID = library.voices.first?.id }
        lastRecording = library.history.max { $0.date < $1.date }
        refreshModelState()
    }

    // MARK: Voices

    var voices: [Voice] {
        library.voices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var selectedVoice: Voice? {
        library.voice(selectedVoiceID)
    }

    func clipURL(for voice: Voice) -> URL {
        voicesFolder.appendingPathComponent(voice.clipFileName)
    }

    /// Saves a new voice from a prepared clip (mono, 24 kHz, trimmed).
    @discardableResult
    func addVoice(name: String, transcript: String, samples: [Float]) throws -> Voice {
        let cleanName = try VoiceRules.name(name, existing: library.voices)
        let cleanTranscript = try VoiceRules.transcript(transcript)
        let check = try ReferenceCheck.check(samples, sampleRate: VoiceEngine.sampleRate)
        let voice = Voice(name: cleanName, transcript: cleanTranscript, seconds: check.seconds)
        try FileManager.default.createDirectory(at: voicesFolder, withIntermediateDirectories: true)
        try WAVFile.write(samples: samples, sampleRate: VoiceEngine.sampleRate, to: clipURL(for: voice))
        library.voices.append(voice)
        save()
        selectedVoiceID = voice.id
        statusMessage = "Saved the voice “\(voice.name)”."
        return voice
    }

    func updateVoice(_ id: UUID, name: String, transcript: String) throws {
        guard let index = library.voices.firstIndex(where: { $0.id == id }) else { return }
        let cleanName = try VoiceRules.name(name, existing: library.voices, excluding: id)
        let cleanTranscript = try VoiceRules.transcript(transcript)
        library.voices[index].name = cleanName
        library.voices[index].transcript = cleanTranscript
        save()
        statusMessage = "Saved changes to “\(cleanName)”."
    }

    /// Removes a voice. Its clip goes to the Trash, so it can still be recovered from there.
    func deleteVoice(_ id: UUID) {
        guard let voice = library.voice(id) else { return }
        let clip = clipURL(for: voice)
        if playback.currentURL == clip { playback.stop() }
        try? FileManager.default.trashItem(at: clip, resultingItemURL: nil)
        library.voices.removeAll { $0.id == id }
        if selectedVoiceID == id { selectedVoiceID = voices.first?.id }
        save()
        statusMessage = "Deleted “\(voice.name)”. Its clip is in the Trash; your recordings are kept."
    }

    // MARK: Recording

    var isGenerating: Bool { generationTask != nil }

    /// Generates audio from the Generate page's script in the selected voice.
    func generate() {
        guard let voice = selectedVoice else {
            errorMessage = "Add a voice first (Voices → Add Voice…)."
            return
        }
        start(script: script, direction: direction, voice: voice, seed: UInt64.random(in: 0 ... UInt64.max), quality: quality)
    }

    /// Generates a recording again from Recordings: the same take (same seed and model quality) or a new one.
    func regenerate(_ item: HistoryItem, sameTake: Bool) {
        guard let voice = library.voice(item.voiceID) else {
            errorMessage = "The voice “\(item.voiceName)” was deleted, so this audio can't be generated again."
            return
        }
        script = item.script
        direction = item.direction ?? ""
        selectedVoiceID = voice.id
        section = .generate
        start(script: item.script, direction: item.direction ?? "", voice: voice,
              seed: sameTake ? item.seed : UInt64.random(in: 0 ... UInt64.max),
              quality: sameTake ? item.quality : quality)
    }

    func stop() {
        generationTask?.cancel()
    }

    private func start(script: String, direction: String, voice: Voice, seed: UInt64, quality: ModelQuality) {
        guard generationTask == nil else { return }
        guard downloadTask == nil else {
            errorMessage = "The voice model is still downloading. Generate audio when the download finishes."
            return
        }
        let plan: GenerationPlan
        do {
            plan = try GenerationPlan(script: script, seed: seed)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        errorMessage = nil
        statusMessage = nil
        unloadTask?.cancel()
        playback.stop()
        let trimmedDirection = direction.trimmingCharacters(in: .whitespacesAndNewlines)
        let clip = clipURL(for: voice)
        generationTask = Task { [weak self] in
            await self?.run(script: script, plan: plan, voice: voice, clip: clip, direction: trimmedDirection.isEmpty ? nil : trimmedDirection, quality: quality)
            self?.generationTask = nil
            self?.progress = nil
            self?.refreshModelState()
            self?.scheduleUnload()
        }
    }

    private func run(script: String, plan: GenerationPlan, voice: Voice, clip: URL, direction: String?, quality: ModelQuality) async {
        let started = Date()
        do {
            progress = GenerationProgress(part: 0, parts: plan.parts.count, secondsLeft: nil, stage: "Getting your voice ready…")
            let reference = try await Task.detached(priority: .userInitiated) {
                try AudioFileReader.monoSamples(from: clip, sampleRate: VoiceEngine.sampleRate)
            }.value
            try await prepareModel(quality)
            var pieces: [[Float]] = []
            var cutOff: [Int] = []
            let partsStarted = Date()
            for (index, part) in plan.parts.enumerated() {
                try Task.checkCancellation()
                progress = GenerationProgress(
                    part: index + 1, parts: plan.parts.count,
                    secondsLeft: plan.remainingSeconds(finishedParts: index, elapsed: Date().timeIntervalSince(partsStarted)),
                    stage: plan.parts.count == 1 ? "Speaking…" : "Speaking part \(index + 1) of \(plan.parts.count)…"
                )
                let result = try await engine.speak(text: part.text, direction: direction, reference: reference,
                                                    referenceText: voice.transcript, seed: plan.seed(forPart: index))
                pieces.append(result.samples)
                if GenerationPlan.wasCutOff(steps: result.steps) { cutOff.append(index + 1) }
            }
            progress = GenerationProgress(part: plan.parts.count, parts: plan.parts.count, secondsLeft: nil, stage: "Saving…")
            let samples = AudioTools.join(pieces, pauses: plan.parts.map(\.pauseAfter), sampleRate: VoiceEngine.sampleRate)
            try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
            let date = Date()
            let url = FileNaming.unique(FileNaming.recordingName(voiceName: voice.name, date: date), in: outputFolder)
            try WAVFile.write(samples: samples, sampleRate: VoiceEngine.sampleRate, to: url)
            let item = HistoryItem(
                date: date, voiceID: voice.id, voiceName: voice.name, script: script.trimmingCharacters(in: .whitespacesAndNewlines),
                direction: direction, filePath: url.path,
                seconds: AudioTools.duration(sampleCount: samples.count, sampleRate: VoiceEngine.sampleRate),
                seed: plan.seed, quality: quality, cutOffParts: cutOff, generationSeconds: Date().timeIntervalSince(started)
            )
            library.history.append(item)
            save()
            lastRecording = item
            statusMessage = "Saved “\(item.fileName)” (\(TimeText.clock(item.seconds)))."
            if playWhenDone { playback.play(url) }
        } catch is CancellationError {
            statusMessage = "Stopped. Nothing was saved."
        } catch {
            if Task.isCancelled {
                statusMessage = "Stopped. Nothing was saved."
            } else {
                errorMessage = "Couldn't generate audio: \(error.localizedDescription)"
            }
        }
    }

    // MARK: New script

    /// What New Script cleared, so its "Undo" can put it back.
    private var newScriptUndo: (message: String, script: String, direction: String)?

    /// True while the "New script started." message (with its Undo button) is showing.
    var canUndoNewScript: Bool {
        guard let undo = newScriptUndo else { return false }
        return undo.message == statusMessage
    }

    /// Clears the script and delivery style for a fresh start. The voice, the latest audio and the
    /// saved recordings stay as they are.
    func newScript() {
        // Nothing to clear: keep the earlier undo copy instead of replacing it with blanks.
        guard !isGenerating, !(script.isEmpty && direction.isEmpty) else { return }
        let message = "New script started."
        newScriptUndo = (message: message, script: script, direction: direction)
        script = ""
        direction = ""
        errorMessage = nil
        statusMessage = message
    }

    /// Puts back the script and delivery style that New Script cleared.
    func undoNewScript() {
        guard let undo = newScriptUndo else { return }
        newScriptUndo = nil
        script = undo.script
        direction = undo.direction
        statusMessage = "Script restored."
    }

    // MARK: The voice model

    private func prepareModel(_ quality: ModelQuality) async throws {
        if !engine.isDownloaded(quality) { modelState = .downloading(0) } else { modelState = .loading }
        try await engine.prepare(quality) { [weak self] fraction in
            guard let self else { return }
            if fraction < 1 {
                self.modelState = .downloading(fraction)
            } else {
                self.modelState = .loading
            }
        }
        modelState = .ready
    }

    /// Downloads the chosen quality ahead of time, so the first recording starts right away.
    func downloadModel() {
        guard downloadTask == nil, !isGenerating else { return }
        let quality = self.quality
        modelState = .downloading(0)
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.engine.download(quality) { [weak self] fraction in
                    self?.modelState = .downloading(fraction)
                }
                self.statusMessage = "The voice model is downloaded. You're ready to go."
            } catch {
                if error is CancellationError || Task.isCancelled {
                    self.statusMessage = "Download stopped. It picks up from the start next time."
                } else {
                    self.errorMessage = "The download didn't finish: \(error.localizedDescription) Check your internet connection and try again."
                }
            }
            self.downloadTask = nil
            self.refreshModelState()
        }
    }

    var isDownloading: Bool { downloadTask != nil }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func isDownloaded(_ quality: ModelQuality) -> Bool {
        engine.isDownloaded(quality)
    }

    /// Moves a downloaded quality to the Trash to free disk space.
    func removeModel(_ quality: ModelQuality) {
        guard !isGenerating, !isDownloading else { return }
        Task {
            let loaded = await engine.loadedQuality
            if loaded == quality { await engine.unload() }
            try? FileManager.default.trashItem(at: engine.folder(for: quality), resultingItemURL: nil)
            refreshModelState()
            statusMessage = "Moved the \(quality.shortTitle) model to the Trash. Empty the Trash to free the disk space."
        }
    }

    /// Frees up the model's memory now. It loads again before the next generation.
    func freeMemory() {
        guard !isGenerating else { return }
        unloadTask?.cancel()
        Task {
            await engine.unload()
            refreshModelState()
            statusMessage = "Memory freed up. The voice model loads again before your next generation."
        }
    }

    private func scheduleUnload() {
        unloadTask?.cancel()
        let minutes = unloadAfterMinutes
        guard minutes > 0 else { return }
        unloadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled, let self, !self.isGenerating else { return }
            await self.engine.unload()
            self.refreshModelState()
        }
    }

    func refreshModelState() {
        if case .downloading = modelState, downloadTask != nil || isGenerating { return }
        let quality = self.quality
        Task {
            let loaded = await engine.loadedQuality
            if case .downloading = modelState, downloadTask != nil || isGenerating { return }
            if loaded == quality {
                modelState = .ready
            } else {
                modelState = engine.isDownloaded(quality) ? .idle : .notDownloaded
            }
        }
    }

    // MARK: Recordings

    func deleteRecording(_ item: HistoryItem) {
        let url = URL(fileURLWithPath: item.filePath)
        if playback.currentURL == url { playback.stop() }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        library.history.removeAll { $0.id == item.id }
        if lastRecording?.id == item.id { lastRecording = library.history.max { $0.date < $1.date } }
        save()
        statusMessage = "Moved “\(item.fileName)” to the Trash."
    }

    /// Clears the list; the audio files stay where they are.
    func clearHistory() {
        library.history.removeAll()
        lastRecording = nil
        save()
        statusMessage = "Recordings list cleared. The audio files are still in \(outputFolder.lastPathComponent)."
    }

    func fileExists(_ item: HistoryItem) -> Bool {
        FileManager.default.fileExists(atPath: item.filePath)
    }

    func reveal(_ item: HistoryItem) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.filePath)])
    }

    func useScript(_ item: HistoryItem) {
        script = item.script
        direction = item.direction ?? ""
        if library.voice(item.voiceID) != nil { selectedVoiceID = item.voiceID }
        section = .generate
    }

    // MARK: Output folder

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Save recordings in"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputFolder = url
        defaults.set(url.path, forKey: Keys.outputFolder)
        statusMessage = "New recordings will be saved in \(url.lastPathComponent)."
    }

    func showOutputFolder() {
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(outputFolder)
    }

    private func save() {
        do {
            try store.save(library)
        } catch {
            errorMessage = "Couldn't save EchoVoice's library: \(error.localizedDescription)"
        }
    }
}
