import Foundation

/// A saved voice: a short clip of someone speaking and the exact words they say in it.
public struct Voice: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var transcript: String
    public var seconds: Double
    public var created: Date

    public init(id: UUID = UUID(), name: String, transcript: String, seconds: Double, created: Date = Date()) {
        self.id = id
        self.name = name
        self.transcript = transcript
        self.seconds = seconds
        self.created = created
    }

    /// The clip's file name inside the Voices folder.
    public var clipFileName: String { "\(id.uuidString).wav" }
}

/// One finished recording.
public struct HistoryItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var voiceID: UUID
    public var voiceName: String
    public var script: String
    /// The optional delivery direction, such as "warm and slow".
    public var direction: String?
    public var filePath: String
    public var seconds: Double
    public var seed: UInt64
    public var quality: ModelQuality
    /// Parts (1-based) that reached the model's length limit and may be cut off.
    public var cutOffParts: [Int]
    public var generationSeconds: Double

    public init(id: UUID = UUID(), date: Date = Date(), voiceID: UUID, voiceName: String, script: String, direction: String?,
                filePath: String, seconds: Double, seed: UInt64, quality: ModelQuality, cutOffParts: [Int], generationSeconds: Double) {
        self.id = id
        self.date = date
        self.voiceID = voiceID
        self.voiceName = voiceName
        self.script = script
        self.direction = direction
        self.filePath = filePath
        self.seconds = seconds
        self.seed = seed
        self.quality = quality
        self.cutOffParts = cutOffParts
        self.generationSeconds = generationSeconds
    }

    public var fileName: String { URL(fileURLWithPath: filePath).lastPathComponent }
}

/// Which download of Breeze TTS 2 to run. All three use the same model; smaller ones are faster.
public enum ModelQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard
    case best
    case faster

    public var id: String { rawValue }

    public var repository: String {
        switch self {
        case .standard: return "mlx-community/Breeze-TTS-2-mlx-8bit"
        case .best: return "mlx-community/Breeze-TTS-2-mlx"
        case .faster: return "mlx-community/Breeze-TTS-2-mlx-4bit"
        }
    }

    public var title: String {
        switch self {
        case .standard: return "Standard (recommended)"
        case .best: return "Best quality (slower)"
        case .faster: return "Faster"
        }
    }

    public var detail: String {
        switch self {
        case .standard: return "Sounds like Best quality to most ears, at about twice the speed. About 4 GB of memory while in use."
        case .best: return "The full model. Slowest, about 7 GB of memory while in use."
        case .faster: return "The quickest and smallest. You may hear a small drop in quality. About 3 GB of memory."
        }
    }
}

public enum VoiceRules {
    public static let maximumNameLength = 80
    public static let maximumTranscriptLength = 2_000

    public enum Problem: Error, Equatable, LocalizedError {
        case emptyName
        case nameTooLong
        case duplicateName(String)
        case emptyTranscript
        case transcriptTooLong

        public var errorDescription: String? {
            switch self {
            case .emptyName: return "Give this voice a name."
            case .nameTooLong: return "Use a shorter name (up to 80 characters)."
            case .duplicateName(let name): return "You already have a voice named “\(name)”. Pick another name."
            case .emptyTranscript: return "Type the exact words spoken in the clip, or let EchoVoice transcribe it."
            case .transcriptTooLong: return "That transcript is too long for a voice clip. Use a shorter clip."
            }
        }
    }

    /// The cleaned-up name, or the reason it can't be used. `excluding` is the voice being renamed.
    public static func name(_ raw: String, existing: [Voice], excluding: UUID? = nil) throws -> String {
        let name = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !name.isEmpty else { throw Problem.emptyName }
        guard name.count <= maximumNameLength else { throw Problem.nameTooLong }
        if let clash = existing.first(where: { $0.id != excluding && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            throw Problem.duplicateName(clash.name)
        }
        return name
    }

    public static func transcript(_ raw: String) throws -> String {
        let text = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty else { throw Problem.emptyTranscript }
        guard text.count <= maximumTranscriptLength else { throw Problem.transcriptTooLong }
        return text
    }
}

/// Everything EchoVoice remembers, saved as one JSON file.
public struct LibraryState: Codable, Equatable, Sendable {
    public var voices: [Voice] = []
    public var history: [HistoryItem] = []

    public init(voices: [Voice] = [], history: [HistoryItem] = []) {
        self.voices = voices
        self.history = history
    }

    public func voice(_ id: UUID?) -> Voice? {
        guard let id else { return nil }
        return voices.first { $0.id == id }
    }

    /// History, newest first, matching every word of `query` in the script, voice name or file name.
    public func searchHistory(_ query: String) -> [HistoryItem] {
        let sorted = history.sorted { $0.date > $1.date }
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return sorted }
        return sorted.filter { item in
            let haystack = [item.script, item.voiceName, item.fileName, item.direction ?? ""].joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}

/// Reads and writes the library file. A damaged file is set aside instead of being overwritten.
public struct LibraryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func load() -> LibraryState {
        guard let data = try? Data(contentsOf: fileURL) else { return LibraryState() }
        do {
            return try Self.decoder.decode(LibraryState.self, from: data)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = fileURL.deletingPathExtension().appendingPathExtension("damaged-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            return LibraryState()
        }
    }

    public func save(_ state: LibraryState) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(state).write(to: fileURL, options: .atomic)
    }
}

public enum FileNaming {
    /// "EchoVoice – Jordan – 2026-10-13 at 14.05.22.wav", safe for Finder.
    public static func recordingName(voiceName: String, date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?) -> String {
            let number = value ?? 0
            return number < 10 ? "0\(number)" : "\(number)"
        }
        let stamp = "\(parts.year ?? 0)-\(pad(parts.month))-\(pad(parts.day)) at \(pad(parts.hour)).\(pad(parts.minute)).\(pad(parts.second))"
        return "EchoVoice – \(safe(voiceName)) – \(stamp).wav"
    }

    /// Removes characters Finder or other apps dislike, and keeps names short.
    public static func safe(_ text: String) -> String {
        var kept = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !CharacterSet.controlCharacters.contains(scalar) && !"/\\:".unicodeScalars.contains(scalar) {
            kept.append(scalar)
        }
        let clean = String(kept).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let short = clean.count > 40 ? String(clean.prefix(40)).trimmingCharacters(in: .whitespaces) : clean
        return short.isEmpty ? "Voice" : short
    }

    /// `name` in `folder`, or "name 2", "name 3"… if it's taken.
    public static func unique(_ name: String, in folder: URL, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var number = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        return candidate
    }
}

public enum TimeText {
    /// "0:07", "1:05", "1:02:03".
    public static func clock(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        let paddedSeconds = secs < 10 ? "0\(secs)" : "\(secs)"
        if hours > 0 {
            let paddedMinutes = minutes < 10 ? "0\(minutes)" : "\(minutes)"
            return "\(hours):\(paddedMinutes):\(paddedSeconds)"
        }
        return "\(minutes):\(paddedSeconds)"
    }
}
