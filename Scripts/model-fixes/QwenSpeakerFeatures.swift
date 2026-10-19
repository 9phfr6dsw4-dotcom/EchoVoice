import Foundation
import MLX
import MLXAudioCore

/// Qwen's speaker encoder was trained on log-magnitude Slaney features, rather than
/// the power/log10 features used by Whisper. Keep this separate from shared DSP.
/// Input is mono 24 kHz; output is [frames, 128].
public func echoVoiceQwenSpeakerFeatures(_ audio: MLXArray) -> MLXArray {
    let samples = audio.asArray(Float.self)
    let fftSize = 1024
    let hop = 256
    let padding = (fftSize - hop) / 2
    precondition(audio.ndim == 1 && samples.count > padding, "Qwen needs a mono reference clip.")
    let prefix = Array(samples[1...padding].reversed())
    let suffix = Array(samples[(samples.count - padding - 1)..<(samples.count - 1)].reversed())
    let padded = MLXArray(prefix + samples + suffix)
    let frameCount = 1 + (padded.size - fftSize) / hop
    let frames = asStrided(padded, [frameCount, fftSize], strides: [hop, 1])
    let spectrum = MLXFFT.rfft(frames * hanningWindow(size: fftSize, periodic: true), axis: 1)
    let magnitude = sqrt(MLX.abs(spectrum).square() + Float(1e-9))
    let filters = melFilters(sampleRate: 24_000, nFft: fftSize, nMels: 128,
        fMin: 0, fMax: 12_000, norm: "slaney", melScale: .slaney)
    return log(maximum(matmul(magnitude, filters), MLXArray(Float(1e-5))))
}
