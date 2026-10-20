import Foundation
import XCTest
@testable import EchoVoiceCore

final class ScriptSplitterTests: XCTestCase {
    func testSentencesRespectAbbreviationsDecimalsAndChinese() {
        let text = "Dr. Smith arrived at 3.5 p.m. today. He said \"Hello!\" Then left... J. K. Rowling wrote it. 你好。我很好！真的？"
        XCTAssertEqual(ScriptSplitter.sentences(in: text), [
            "Dr. Smith arrived at 3.5 p.m. today.",
            "He said \"Hello!\"",
            "Then left...",
            "J. K. Rowling wrote it.",
            "你好。", "我很好！", "真的？"
        ])
    }

    func testParagraphsAreSeparatedByBlankLines() {
        XCTAssertEqual(ScriptSplitter.paragraphs(in: "Line one\nline two.\n\n\n  Second para.\r\nStill second."),
                       ["Line one line two.", "Second para. Still second."])
        XCTAssertEqual(ScriptSplitter.paragraphs(in: " \n\n \t\n"), [])
    }

    func testPartsPackSentencesWithPauses() {
        XCTAssertEqual(ScriptSplitter.split("First sentence. Second one!\n\nNew paragraph here."), [
            ScriptPart(text: "First sentence. Second one!", pauseAfter: 0.6),
            ScriptPart(text: "New paragraph here.", pauseAfter: 0)
        ])
        XCTAssertEqual(ScriptSplitter.split("Alpha beta gamma. Delta epsilon zeta. Eta theta iota.", maxCharacters: 40), [
            ScriptPart(text: "Alpha beta gamma. Delta epsilon zeta.", pauseAfter: 0.25),
            ScriptPart(text: "Eta theta iota.", pauseAfter: 0)
        ])
        XCTAssertEqual(ScriptSplitter.split("   \n\n  "), [])
    }

    func testLongSentencesBreakAtCommasThenWords() {
        let words = Array(repeating: "word", count: 30).joined(separator: " ")
        let parts = ScriptSplitter.split("One, two, three; " + words + ".", maxCharacters: 40)
        XCTAssertEqual(parts.map(\.text), [
            "One, two, three; word word word word",
            "word word word word word word word word",
            "word word word word word word word word",
            "word word word word word word word word",
            "word word."
        ])
        XCTAssertTrue(parts.allSatisfy { $0.text.count <= 40 })
        // A single huge "word" (for example a long link) is cut into pieces that fit.
        let link = String(repeating: "x", count: 95)
        XCTAssertEqual(ScriptSplitter.split(link, maxCharacters: 40).map { $0.text.count }, [40, 40, 15])
    }

    func testEveryWordSurvivesSplitting() {
        let script = """
        Hey, this is a longer script. It has several sentences, some of them with commas, and a few questions? Yes!

        A second paragraph follows. It ends here.
        """
        let parts = ScriptSplitter.split(script, maxCharacters: 50)
        let rejoined = parts.map(\.text).joined(separator: " ").split(separator: " ")
        let original = script.split(whereSeparator: { $0.isWhitespace })
        XCTAssertEqual(rejoined, original)
    }
}

final class AudioToolsTests: XCTestCase {
    func testWAVHeaderAndSamples() {
        let data = WAVFile.encode(samples: [0, 0.5, -1, 2, .nan], sampleRate: 24_000)
        XCTAssertEqual(data.count, 44 + 10)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<16], as: UTF8.self), "WAVEfmt ")
        func uint32(_ offset: Int) -> UInt32 { data[offset..<offset + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) } }
        func int16(_ offset: Int) -> Int16 { Int16(bitPattern: UInt16(data[offset]) | UInt16(data[offset + 1]) << 8) }
        XCTAssertEqual(uint32(4), 46)
        XCTAssertEqual(uint32(24), 24_000)
        XCTAssertEqual(uint32(28), 48_000)
        XCTAssertEqual(uint32(40), 10)
        XCTAssertEqual((44..<54).filter { $0 % 2 == 0 }.map(int16), [0, 16384, -32767, 32767, 0])
    }

    func testWriteLeavesNoPartialFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EchoVoiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("take.wav")
        try WAVFile.write(samples: [0.1, 0.2], sampleRate: 24_000, to: url)
        XCTAssertEqual(try Data(contentsOf: url).count, 48)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["take.wav"])
        XCTAssertThrowsError(try WAVFile.write(samples: [0], sampleRate: 24_000, to: url))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["take.wav"])
    }

    func testJoinAddsPausesBetweenPartsOnly() {
        let joined = AudioTools.join([[1, 1], [2], [3]], pauses: [0.5, 0.25, 9], sampleRate: 4)
        XCTAssertEqual(joined, [1, 1, 0, 0, 2, 0, 3])
    }

    func testTrimSilenceKeepsAMargin() {
        let samples: [Float] = [0, 0, 0, 0, 0.5, 0.2, 0, 0, 0, 0]
        XCTAssertEqual(AudioTools.trimSilence(samples, sampleRate: 10, keep: 0.1), [0, 0.5, 0.2, 0])
        XCTAssertEqual(AudioTools.trimSilence([0, 0.001], sampleRate: 10), [])
    }

    func testQuietClipsAreRaisedLoudOnesKept() {
        let raised = AudioTools.normalizedIfQuiet([0.1, -0.2])
        XCTAssertEqual(raised[0], 0.45, accuracy: 0.0001)
        XCTAssertEqual(raised[1], -0.9, accuracy: 0.0001)
        XCTAssertEqual(AudioTools.normalizedIfQuiet([0.8, -0.5]), [0.8, -0.5])
    }

    func testReferenceCheck() throws {
        let rate = 100
        XCTAssertThrowsError(try ReferenceCheck.check([Float](repeating: 0.0005, count: 500), sampleRate: rate)) {
            XCTAssertEqual($0 as? ReferenceCheck.Problem, .silent)
        }
        XCTAssertThrowsError(try ReferenceCheck.check([Float](repeating: 0.3, count: 250), sampleRate: rate)) {
            XCTAssertEqual($0 as? ReferenceCheck.Problem, .tooShort(2.5))
        }
        XCTAssertThrowsError(try ReferenceCheck.check([Float](repeating: 0.3, count: 6_100), sampleRate: rate)) {
            XCTAssertEqual($0 as? ReferenceCheck.Problem, .tooLong(61))
        }
        let good = try ReferenceCheck.check([Float](repeating: 0.3, count: 1_200), sampleRate: rate)
        XCTAssertEqual(good, ReferenceCheck.Result(seconds: 12, notes: []))
        var loud = [Float](repeating: 0.3, count: 3_000)
        for index in 0..<10 { loud[index] = 1 }
        let result = try ReferenceCheck.check(loud, sampleRate: rate)
        XCTAssertEqual(result.seconds, 30)
        XCTAssertEqual(result.notes.count, 2)
    }
}

final class LibraryTests: XCTestCase {
    func testVoiceNamesAreCleanAndUnique() throws {
        let alex = Voice(name: "Alex", transcript: "Hi.", seconds: 10)
        XCTAssertEqual(try VoiceRules.name("  Alex   take 2 ", existing: [alex]), "Alex take 2")
        XCTAssertThrowsError(try VoiceRules.name("ALEX", existing: [alex])) {
            XCTAssertEqual($0 as? VoiceRules.Problem, .duplicateName("Alex"))
        }
        XCTAssertEqual(try VoiceRules.name("alex", existing: [alex], excluding: alex.id), "alex")
        XCTAssertThrowsError(try VoiceRules.name("   ", existing: []))
        XCTAssertThrowsError(try VoiceRules.name(String(repeating: "a", count: 81), existing: []))
        XCTAssertEqual(try VoiceRules.transcript(" Hello\n there. "), "Hello there.")
        XCTAssertThrowsError(try VoiceRules.transcript("  "))
    }

    func testHistorySearchMatchesEveryWordNewestFirst() {
        let voice = UUID()
        func item(_ script: String, _ age: Double, name: String = "Alex") -> HistoryItem {
            HistoryItem(date: Date(timeIntervalSince1970: 1_000_000 - age), voiceID: voice, voiceName: name, script: script, direction: nil,
                        filePath: "/tmp/\(script).wav", seconds: 3, seed: 1, cutOffParts: [], generationSeconds: 5)
        }
        let state = LibraryState(history: [item("Weekly update for the team", 50), item("Birthday message", 10), item("Team birthday", 30, name: "Sam")])
        XCTAssertEqual(state.searchHistory("").map(\.script), ["Birthday message", "Team birthday", "Weekly update for the team"])
        XCTAssertEqual(state.searchHistory("team").map(\.script), ["Team birthday", "Weekly update for the team"])
        XCTAssertEqual(state.searchHistory("BIRTHDAY sam").map(\.script), ["Team birthday"])
    }

    func testStoreRoundTripAndDamagedFileIsSetAside() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EchoVoiceStore-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(fileURL: folder.appendingPathComponent("library.json"))
        XCTAssertEqual(store.load(), LibraryState())
        let voice = Voice(name: "Alex", transcript: "Hi there.", seconds: 12.5, created: Date(timeIntervalSince1970: 1_700_000_000))
        let state = LibraryState(voices: [voice])
        try store.save(state)
        XCTAssertEqual(store.load(), state)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(store.load(), LibraryState())
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("library.damaged-") }, "\(names)")
    }

    func testFileNames() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_791_900_322)
        XCTAssertEqual(FileNaming.recordingName(voiceName: "Alex / take: 2", date: date, calendar: calendar),
                       "EchoVoice – Alex take 2 – 2026-10-13 at 14.05.22.wav")
        XCTAssertEqual(FileNaming.safe("..."), "Voice")
        XCTAssertEqual(FileNaming.safe(String(repeating: "a", count: 50)).count, 40)
        let folder = URL(fileURLWithPath: "/x")
        let taken: Set<String> = ["/x/a.wav", "/x/a 2.wav"]
        XCTAssertEqual(FileNaming.unique("a.wav", in: folder, exists: { taken.contains($0.path) }).path, "/x/a 3.wav")
        XCTAssertEqual(FileNaming.unique("b.wav", in: folder, exists: { taken.contains($0.path) }).path, "/x/b.wav")
    }

    func testWordCount() {
        let script = "Welcome back. Today, I’m sharing a few ideas I’ve been thinking about. Let’s get started."
        XCTAssertEqual(ScriptStats.wordCount(script), 15)
        XCTAssertEqual(ScriptStats.wordLabel(script), "15 words")
        XCTAssertEqual(ScriptStats.wordLabel("Hello"), "1 word")
        XCTAssertEqual(ScriptStats.wordLabel("  \n "), "")
        XCTAssertEqual(ScriptStats.wordCount("one — two\n\nthree"), 3)
        XCTAssertEqual(ScriptStats.wordCount("你好。我很好！"), 5)
        XCTAssertEqual(ScriptStats.wordCount("Echo说你好"), 4)
    }

    func testVoiceModel() {
        XCTAssertEqual(VoiceModel.allCases, [.breeze])
        XCTAssertEqual(VoiceModel.breeze.repository, "mlx-community/Breeze-TTS-2-mlx-8bit")
    }

    /// Libraries saved by earlier versions have a "quality" field on each recording; it is ignored.
    func testLibraryFromBreezeEraStillLoads() throws {
        let json = """
        {"id":"\(UUID().uuidString)","date":0,"voiceID":"\(UUID().uuidString)","voiceName":"Ada","script":"Hi.",
         "direction":"calm","filePath":"/tmp/a.wav","seconds":2,"seed":1,"quality":"standard","cutOffParts":[],"generationSeconds":3}
        """
        let item = try JSONDecoder().decode(HistoryItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.direction, "calm")
        XCTAssertEqual(item.voiceName, "Ada")
        XCTAssertNil(item.model)
    }

    /// Load real pre-0.4.0 library shapes, not a current-model encode/decode round trip.
    func testOldLibrariesWithAndWithoutDeliveryStyleKeepLoading() throws {
        for style in ["\"direction\":\"calm, happy\",", "\"direction\":null,", ""] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let store = LibraryStore(fileURL: folder.appendingPathComponent("library.json"))
            let voiceID = UUID().uuidString
            let recordingID = UUID().uuidString
            let json = """
            {"voices":[{"id":"\(voiceID)","name":"Ada","transcript":"Hello.","seconds":10,"created":"2026-10-13T12:00:00Z"}],
             "history":[{"id":"\(recordingID)","date":"2026-10-13T12:00:00Z","voiceID":"\(voiceID)","voiceName":"Ada",
             "script":"Hi.",\(style)"filePath":"/tmp/old-take.wav","seconds":2,"seed":42,"quality":"standard",
             "cutOffParts":[],"generationSeconds":3}]}
            """
            let original = Data(json.utf8)
            try original.write(to: store.fileURL)
            let library = store.load()
            XCTAssertEqual(library.voices.count, 1)
            let item = try XCTUnwrap(library.history.first)
            XCTAssertEqual(item.id.uuidString, recordingID)
            XCTAssertEqual(item.voiceID, library.voices.first?.id)
            XCTAssertEqual(item.filePath, "/tmp/old-take.wav")
            XCTAssertEqual(item.seed, 42)
            XCTAssertEqual(item.direction, style.contains("calm") ? "calm, happy" : nil)
            XCTAssertNil(item.model)
            XCTAssertEqual(try Data(contentsOf: store.fileURL), original, "Loading must not rewrite the old library")
            try store.save(library)
            XCTAssertEqual(store.load(), library)
            let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
            let history = try XCTUnwrap(saved["history"] as? [[String: Any]])
            XCTAssertNil(history[0]["style"], "Keep the original direction key")
            if let direction = item.direction { XCTAssertEqual(history[0]["direction"] as? String, direction) }
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.contains("damaged") })
        }
    }

    func testSavedModelRoundTripAndLegacySelection() throws {
        XCTAssertEqual(VoiceModel.restored(nil), .breeze)
        XCTAssertEqual(VoiceModel.restored("invalid"), .breeze)
        XCTAssertEqual(VoiceModel.restored("chatterbox"), .breeze)
        XCTAssertEqual(VoiceModel.restored("qwen"), .breeze)
        for selected in [VoiceModel.breeze, .qwen, .chatterbox] {
            let item = HistoryItem(date: Date(timeIntervalSince1970: 0), voiceID: UUID(), voiceName: "Ada", script: "Hello.", direction: nil,
                filePath: "/tmp/test.wav", seconds: 2, seed: 42, cutOffParts: [], generationSeconds: 3,
                model: selected)
            let restored = try LibraryStore.decoder.decode(HistoryItem.self, from: LibraryStore.encoder.encode(item))
            XCTAssertEqual(restored, item)
        }
    }

    func testRetiredModelLibrariesKeepVoicesAndAudioPaths() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(fileURL: directory.appendingPathComponent("library.json"))
        // The library's ISO 8601 format stores whole seconds. Use a representable fixture date
        // so this test checks voice/history preservation rather than subsecond clock precision.
        let voice = Voice(name: "Ada", transcript: "", seconds: 10, created: Date(timeIntervalSince1970: 0))
        let history = [VoiceModel.qwen, .chatterbox].map { selected in
            HistoryItem(date: Date(timeIntervalSince1970: 0), voiceID: voice.id, voiceName: voice.name,
                script: "Hello.", direction: nil, filePath: "/tmp/\(selected.rawValue).wav", seconds: 2,
                seed: 42, cutOffParts: [], generationSeconds: 3, model: selected)
        }
        let original = LibraryState(voices: [voice], history: history)
        try store.save(original)
        XCTAssertEqual(store.load(), original)
    }

    func testBreezeRequiresTranscriptForPreviouslyOptionalClips() throws {
        XCTAssertEqual(try VoiceRules.transcript("  ", required: VoiceModel.chatterbox.requiresTranscript), "")
        XCTAssertThrowsError(try VoiceRules.transcript("  ", required: VoiceModel.breeze.requiresTranscript))
    }

    func testClockText() {
        XCTAssertEqual(TimeText.clock(7.4), "0:07")
        XCTAssertEqual(TimeText.clock(65), "1:05")
        XCTAssertEqual(TimeText.clock(3_723), "1:02:03")
        XCTAssertEqual(TimeText.clock(-3), "0:00")
    }
}

final class GenerationPlanTests: XCTestCase {
    func testPlanChecksTheScript() {
        XCTAssertThrowsError(try GenerationPlan(script: " \n ", seed: 1)) {
            XCTAssertEqual($0 as? GenerationPlan.Problem, .emptyScript)
        }
        XCTAssertThrowsError(try GenerationPlan(script: String(repeating: "a", count: 50_001), seed: 1))
        XCTAssertEqual(try GenerationPlan(script: "Hi. There.", seed: 1).parts.count, 1)
    }

    func testPartSeedsAreStableAndDistinct() throws {
        let plan = try GenerationPlan(script: "Hi.", seed: 42)
        XCTAssertEqual(plan.seed(forPart: 0), 0xA759_EA27_D472_7622)
        XCTAssertEqual(plan.seed(forPart: 1), 0xBDD7_3226_2FEB_6E95)
        XCTAssertEqual(plan.seed(forPart: 2), 0x28EF_E333_B266_F103)
        let wrapping = try GenerationPlan(script: "Hi.", seed: .max)
        XCTAssertEqual(wrapping.seed(forPart: 1), 0xE4D9_7177_1B65_2C20)
    }

    func testPagesKeepTheirSizeUpToTheStandardWindowAndGrowBeyondIt() {
        XCTAssertEqual(PageLayout.contentWidth(forWindow: 900), 1080)
        XCTAssertEqual(PageLayout.contentWidth(forWindow: 1080), 1080)
        XCTAssertEqual(PageLayout.contentWidth(forWindow: 1180), 1080)
        XCTAssertEqual(PageLayout.contentWidth(forWindow: 1500), 1400)
        XCTAssertEqual(PageLayout.contentWidth(forWindow: 1920), 1680)
        XCTAssertEqual(PageLayout.contentWidth(forWindow: 5120), 1680)
        XCTAssertEqual(PageLayout.sideColumnWidth(forWindow: 900), 194)
        XCTAssertEqual(PageLayout.sideColumnWidth(forWindow: 1180), 194)
        XCTAssertEqual(PageLayout.sideColumnWidth(forWindow: 1500), 242, accuracy: 0.0001)
        XCTAssertEqual(PageLayout.sideColumnWidth(forWindow: 1920), 290)
        XCTAssertEqual(PageLayout.sideColumnWidth(forWindow: 5120), 290)
    }

    func testCutOffAndRemainingTime() throws {
        XCTAssertTrue(GenerationPlan.wasCutOff(steps: 750))
        XCTAssertFalse(GenerationPlan.wasCutOff(steps: 749))
        let plan = try GenerationPlan(script: "Alpha beta gamma. Delta epsilon zeta. Eta theta iota.", seed: 1, maxCharacters: 40)
        XCTAssertNil(plan.remainingSeconds(finishedParts: 0, elapsed: 10))
        XCTAssertEqual(plan.remainingSeconds(finishedParts: 1, elapsed: 37)!, 15, accuracy: 0.0001)
        XCTAssertNil(plan.remainingSeconds(finishedParts: 2, elapsed: 50))
    }
}
