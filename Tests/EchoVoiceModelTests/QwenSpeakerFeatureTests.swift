import Foundation
import MLX
import MLXAudioTTS
import XCTest

final class QwenSpeakerFeatureTests: XCTestCase {
    private struct Fixture: Decodable {
        let samples: [Float]
        let features: [[Float]]
    }

    /// Compare the actual patched MLX function with independently generated librosa data.
    /// CPU execution validates math on CI without model downloads or a physical GPU.
    func testFeaturesMatchOfficialQwenFrontend() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "qwen-speaker-features", withExtension: "json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        Device.withDefaultDevice(.cpu) {
            let result = echoVoiceQwenSpeakerFeatures(MLXArray(fixture.samples))
            XCTAssertEqual(result.shape, [16, 128])
            let actual = result.asArray(Float.self)
            let expected = fixture.features.flatMap { $0 }
            XCTAssertEqual(actual.count, expected.count)
            for (value, reference) in zip(actual, expected) {
                XCTAssertEqual(value, reference, accuracy: 0.0005)
            }
        }
    }

    func testSilenceUsesQwenNaturalLogFloor() {
        Device.withDefaultDevice(.cpu) {
            let features = echoVoiceQwenSpeakerFeatures(MLXArray([Float](repeating: 0, count: 4096)))
            XCTAssertEqual(features.shape, [16, 128])
            for value in features.asArray(Float.self) {
                XCTAssertEqual(value, log(Float(1e-5)), accuracy: 0.00001)
            }
        }
    }
}
