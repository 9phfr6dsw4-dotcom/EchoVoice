import Foundation

/// Plain WAV files: 16-bit PCM, mono. Works anywhere, plays everywhere.
public enum WAVFile {
    public static func encode(samples: [Float], sampleRate: Int) -> Data {
        let dataSize = samples.count * 2
        var data = Data(capacity: 44 + dataSize)
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        append32(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append32(16)
        append16(1)   // PCM
        append16(1)   // mono
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))
        append16(2)
        append16(16)
        data.append(contentsOf: Array("data".utf8))
        append32(UInt32(dataSize))
        for sample in samples {
            append16(UInt16(bitPattern: pcm16(sample)))
        }
        return data
    }

    /// Clamps to the valid range; anything that isn't a number becomes silence.
    static func pcm16(_ sample: Float) -> Int16 {
        guard sample.isFinite else { return 0 }
        let clamped = min(max(sample, -1), 1)
        return Int16((clamped * 32767).rounded())
    }

    /// Writes the file under a temporary name first, so a half-written file is never left behind.
    public static func write(samples: [Float], sampleRate: Int, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial")
        do {
            try encode(samples: samples, sampleRate: sampleRate).write(to: temporary, options: .atomic)
            try FileManager.default.moveItem(at: temporary, to: url)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}

public enum AudioTools {
    /// Joins the parts of a recording with the given pauses (one per part; the last is usually 0).
    public static func join(_ parts: [[Float]], pauses: [Double], sampleRate: Int) -> [Float] {
        var result: [Float] = []
        result.reserveCapacity(parts.reduce(0) { $0 + $1.count })
        for (index, part) in parts.enumerated() {
            result += part
            let pause = index < pauses.count ? pauses[index] : 0
            if pause > 0, index < parts.count - 1 {
                result += [Float](repeating: 0, count: Int((pause * Double(sampleRate)).rounded()))
            }
        }
        return result
    }

    public static func duration(sampleCount: Int, sampleRate: Int) -> Double {
        sampleRate > 0 ? Double(sampleCount) / Double(sampleRate) : 0
    }

    public static func peak(_ samples: [Float]) -> Float {
        samples.reduce(0) { max($0, $1.isFinite ? abs($1) : 0) }
    }

    /// Removes silence at the start and end, keeping a short natural margin.
    public static func trimSilence(_ samples: [Float], sampleRate: Int, threshold: Float = 0.01, keep: Double = 0.15) -> [Float] {
        guard let first = samples.firstIndex(where: { abs($0) >= threshold }),
              let last = samples.lastIndex(where: { abs($0) >= threshold }) else { return [] }
        let margin = Int(keep * Double(sampleRate))
        let start = max(first - margin, 0)
        let end = min(last + margin, samples.count - 1)
        return Array(samples[start...end])
    }

    /// Scales a quiet recording up so its loudest point is at `target`. Loud recordings are left alone.
    public static func normalizedIfQuiet(_ samples: [Float], target: Float = 0.9) -> [Float] {
        let loudest = peak(samples)
        guard loudest > 0, loudest < target * 0.5 else { return samples }
        let gain = target / loudest
        return samples.map { $0 * gain }
    }
}

/// What makes a good voice clip: one person, 3 to 60 seconds, not silent, not distorted.
public enum ReferenceCheck {
    public static let minimumSeconds = 3.0
    public static let maximumSeconds = 60.0
    /// Shorter clips are faster to use and usually clone just as well.
    public static let idealRange = 8.0...25.0

    public enum Problem: Error, Equatable, LocalizedError {
        case tooShort(Double)
        case tooLong(Double)
        case silent

        public var errorDescription: String? {
            switch self {
            case .tooShort(let seconds):
                return String(format: "This clip is %.1f seconds of speech. Use at least 3 seconds; 8 to 25 works best.", seconds)
            case .tooLong(let seconds):
                return String(format: "This clip is %.0f seconds of speech. Use up to 60 seconds; 8 to 25 works best.", seconds)
            case .silent:
                return "This clip is silent or almost silent. Record again a little closer to the microphone."
            }
        }
    }

    public struct Result: Equatable {
        public var seconds: Double
        /// Advice that doesn't block saving.
        public var notes: [String]
    }

    /// Checks speech that has already had silence trimmed from both ends.
    public static func check(_ samples: [Float], sampleRate: Int) throws -> Result {
        let loudest = AudioTools.peak(samples)
        guard loudest >= 0.001 else { throw Problem.silent }
        let seconds = AudioTools.duration(sampleCount: samples.count, sampleRate: sampleRate)
        if seconds < minimumSeconds { throw Problem.tooShort(seconds) }
        if seconds > maximumSeconds { throw Problem.tooLong(seconds) }
        var notes: [String] = []
        let clipped = samples.reduce(0) { $0 + (abs($1) >= 0.999 ? 1 : 0) }
        if Double(clipped) > Double(samples.count) * 0.001 {
            notes.append("Parts of this clip are distorted (too loud). Moving a little further from the microphone may sound better.")
        }
        if seconds > idealRange.upperBound {
            notes.append("Long clips take a little longer to use each time. 8 to 25 seconds usually clones just as well.")
        }
        return Result(seconds: seconds, notes: notes)
    }
}
