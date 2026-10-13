import Foundation

/// One piece of a script, spoken in a single pass of the voice model.
public struct ScriptPart: Equatable, Sendable {
    public var text: String
    /// Silence to add after this part, in seconds (0 for the last part).
    public var pauseAfter: Double

    public init(text: String, pauseAfter: Double) {
        self.text = text
        self.pauseAfter = pauseAfter
    }
}

/// Splits a script of any length into parts the voice model handles well: whole sentences,
/// packed up to a size that stays far below the model's length limit. Paragraphs get a longer
/// pause than sentences.
public enum ScriptSplitter {
    /// About 25 seconds of speech; the model can produce about a minute per pass.
    public static let defaultMaxCharacters = 400
    public static let sentencePause = 0.25
    public static let paragraphPause = 0.6

    private static let sentenceEnders: Set<Character> = [".", "!", "?", "…", "。", "！", "？"]
    private static let closers: Set<Character> = ["\"", "'", "”", "’", ")", "]", "」", "』"]
    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "e.g", "i.e", "a.m", "p.m", "no", "approx", "inc", "ltd", "co"
    ]

    public static func split(_ script: String, maxCharacters: Int = defaultMaxCharacters) -> [ScriptPart] {
        let limit = max(maxCharacters, 40)
        var parts: [ScriptPart] = []
        for paragraph in paragraphs(in: script) {
            var current = ""
            var paragraphParts: [String] = []
            for sentence in sentences(in: paragraph) {
                for piece in fit(sentence, limit: limit) {
                    if current.isEmpty {
                        current = piece
                    } else if current.count + 1 + piece.count <= limit {
                        current += " " + piece
                    } else {
                        paragraphParts.append(current)
                        current = piece
                    }
                }
            }
            if !current.isEmpty { paragraphParts.append(current) }
            for (index, text) in paragraphParts.enumerated() {
                let isParagraphEnd = index == paragraphParts.count - 1
                parts.append(ScriptPart(text: text, pauseAfter: isParagraphEnd ? paragraphPause : sentencePause))
            }
        }
        if !parts.isEmpty { parts[parts.count - 1].pauseAfter = 0 }
        return parts
    }

    /// Paragraphs are separated by blank lines; single line breaks are read as spaces.
    static func paragraphs(in script: String) -> [String] {
        let normalized = script.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var result: [String] = []
        var lines: [String] = []
        func flush() {
            let joined = collapseSpaces(lines.joined(separator: " "))
            if !joined.isEmpty { result.append(joined) }
            lines = []
        }
        for line in normalized.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else {
                lines.append(line)
            }
        }
        flush()
        return result
    }

    static func collapseSpaces(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Sentences end at . ! ? … (and their Chinese forms), plus any closing quotes or brackets.
    /// Common abbreviations such as "Dr." and single initials don't end a sentence.
    static func sentences(in paragraph: String) -> [String] {
        let characters = Array(paragraph)
        var result: [String] = []
        var start = 0
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard sentenceEnders.contains(character) else {
                index += 1
                continue
            }
            var end = index + 1
            while end < characters.count, sentenceEnders.contains(characters[end]) || closers.contains(characters[end]) {
                end += 1
            }
            let atBoundary = end >= characters.count || characters[end].isWhitespace || isWide(character)
            if atBoundary, !(character == "." && isAbbreviation(characters, dotIndex: index)) {
                let sentence = String(characters[start..<end]).trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty { result.append(sentence) }
                start = end
            }
            index = end
        }
        let rest = String(characters[min(start, characters.count)...]).trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { result.append(rest) }
        return result
    }

    private static func isWide(_ character: Character) -> Bool {
        character == "。" || character == "！" || character == "？"
    }

    private static func isAbbreviation(_ characters: [Character], dotIndex: Int) -> Bool {
        var start = dotIndex
        while start > 0, characters[start - 1].isLetter || characters[start - 1] == "." {
            start -= 1
        }
        let word = String(characters[start..<dotIndex]).lowercased()
        if word.count == 1, word.first?.isLetter == true { return true }
        return abbreviations.contains(word)
    }

    /// A sentence longer than the limit is broken at commas, semicolons, colons or dashes, then
    /// at spaces, and only as a last resort inside a word.
    static func fit(_ sentence: String, limit: Int) -> [String] {
        guard sentence.count > limit else { return [sentence] }
        var pieces: [String] = []
        var current = ""
        for clause in clauses(in: sentence) {
            for word in clause.count > limit ? words(in: clause, limit: limit) : [clause] {
                if current.isEmpty {
                    current = word
                } else if current.count + 1 + word.count <= limit {
                    current += " " + word
                } else {
                    pieces.append(current)
                    current = word
                }
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    private static func clauses(in sentence: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in sentence {
            current.append(character)
            if character == "," || character == ";" || character == ":" || character == "—" || character == "，" || character == "；" {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { result.append(trimmed) }
                current = ""
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { result.append(trimmed) }
        return result
    }

    private static func words(in clause: String, limit: Int) -> [String] {
        var result: [String] = []
        for word in clause.split(separator: " ") {
            var remaining = Substring(word)
            while remaining.count > limit {
                result.append(String(remaining.prefix(limit)))
                remaining = remaining.dropFirst(limit)
            }
            if !remaining.isEmpty { result.append(String(remaining)) }
        }
        return result
    }
}
