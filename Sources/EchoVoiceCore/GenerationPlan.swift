import Foundation

/// How one recording is made: the parts of the script, the seed, and progress along the way.
public struct GenerationPlan: Equatable, Sendable {
    /// The model's per-pass limit, in audio steps (about 12 per second of speech).
    public static let maxStepsPerPart = 750
    public static let maximumScriptCharacters = 50_000

    public var parts: [ScriptPart]
    public var seed: UInt64

    public enum Problem: Error, Equatable, LocalizedError {
        case emptyScript
        case scriptTooLong(Int)

        public var errorDescription: String? {
            switch self {
            case .emptyScript:
                return "Type or paste a script first."
            case .scriptTooLong(let count):
                return "This script is \(count.formatted()) characters. EchoVoice handles up to 50,000 at a time; split it into a few recordings."
            }
        }
    }

    public init(script: String, seed: UInt64, maxCharacters: Int = ScriptSplitter.defaultMaxCharacters) throws {
        let count = script.count
        guard count <= Self.maximumScriptCharacters else { throw Problem.scriptTooLong(count) }
        let parts = ScriptSplitter.split(script, maxCharacters: maxCharacters)
        guard !parts.isEmpty else { throw Problem.emptyScript }
        self.parts = parts
        self.seed = seed
    }

    /// Each part gets its own seed derived from the recording's seed, so a whole recording can be
    /// made again the same way and changing one part never shifts the others.
    public func seed(forPart index: Int) -> UInt64 {
        var value = seed &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// A part that used every step it was allowed probably got cut off.
    public static func wasCutOff(steps: Int) -> Bool {
        steps >= maxStepsPerPart
    }

    public var totalCharacters: Int {
        parts.reduce(0) { $0 + $1.text.count }
    }

    /// Seconds left, judged from how long the finished parts took per character. Nil until a part is done.
    public func remainingSeconds(finishedParts: Int, elapsed: Double) -> Double? {
        guard finishedParts > 0, finishedParts < parts.count, elapsed > 0 else { return nil }
        let done = parts[..<finishedParts].reduce(0) { $0 + $1.text.count }
        guard done > 0 else { return nil }
        let left = totalCharacters - done
        return elapsed / Double(done) * Double(left)
    }
}
