#!/usr/bin/env python3
"""Apply narrow, verified fixes to the pinned MLX dependency; never change shared DSP.

A changed upstream file requires review and a new hash, rather than a best-effort patch.
The patched copies are checked too, so rerunning is safe and tampering is rejected.
"""
import hashlib
from pathlib import Path
import subprocess
import sys

REVISION = '244458d7b61e54ff135073ddc9ed76782bb20758'
ROOT = Path(__file__).resolve().parent

def replace_once(text, old, new):
    if text.count(old) != 1:
        raise RuntimeError(f'Expected one patch anchor: {old[:80]!r}')
    return text.replace(old, new)

def qwen_patch(text):
    text = replace_once(text, 'let audioID: ObjectIdentifier', 'let audio: MLXArray')
    text = text.replace('cached.audioID == audioID', 'ObjectIdentifier(cached.audio) == audioID')
    text = replace_once(text, '            audioID: audioID,', '            audio: refAudio,')
    return replace_once(text, '''let mel = computeMelSpectrogram(
                audio: waveform,
                sampleRate: speakerEncoder.config.sampleRate,
                nFft: 1024,
                hopLength: 256,
                nMels: 128
            )''', 'let mel = echoVoiceQwenSpeakerFeatures(waveform)')

def chatterbox_patch(text):
    text = replace_once(text, '    private var modelDir: URL?', '''    private var modelDir: URL?
    public private(set) var echoVoiceGenerationTokenCount = 0''')
    assert text.count('maxNewTokens: maxTokens,') == 2
    text = text.replace('maxNewTokens: maxTokens,', 'maxNewTokens: min(maxTokens, max(1, generationParameters.maxTokens ?? maxTokens)),')
    text = replace_once(text, '        eval(speechTokens)\n', '        eval(speechTokens)\n        echoVoiceGenerationTokenCount = speechTokens.size\n')
    text = replace_once(text, 'generationTokenCount: audio.dim(audio.ndim - 1),', 'generationTokenCount: self.echoVoiceGenerationTokenCount,')
    text = replace_once(text, '''        _ modelDir: URL,
        hfToken: String?
    ) async throws -> ChatterboxModel''', '''        _ modelDir: URL,
        hfToken: String?,
        s3TokenizerDirectory: URL? = nil
    ) async throws -> ChatterboxModel''')
    return replace_once(text, '''        do {
            model.s3Tokenizer = try await S3TokenizerV2.fromPretrained(''', '''        if let s3TokenizerDirectory {
            // EchoVoice supplies a complete local download. Never substitute another voice.
            model.s3Tokenizer = try S3TokenizerV2.fromModelDirectory(s3TokenizerDirectory)
        } else { do {
            model.s3Tokenizer = try await S3TokenizerV2.fromPretrained(''').replace('''        return model
    }
}

// MARK: - Weight Loading''', '''        }
        return model
    }
}

// MARK: - Weight Loading''')

PATCHES = [
    ('Qwen3TTS/Qwen3TTS.swift', 'e0e4ac8efdfb5f63a9e0afc8339b7b2b2a3ac3afe6d749979342f178a70a5df4', qwen_patch),
    ('Chatterbox/ChatterboxModel.swift', '1af5d1804a6038ddd72b13b9b653aebc1d6a3728e5a1910e75ee0c4125a0dc6e', chatterbox_patch),
]

def patch(checkout):
    actual = subprocess.check_output(['git', '-C', str(checkout), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != REVISION:
        raise RuntimeError(f'MLX revision changed: expected {REVISION}, got {actual}')
    models = checkout / 'Sources/MLXAudioTTS/Models'
    changes = []
    # Validate every source before changing any file.
    for relative, digest, transform in PATCHES:
        path = models / relative
        original = subprocess.check_output(['git', '-C', str(checkout), 'show', f'HEAD:Sources/MLXAudioTTS/Models/{relative}'])
        if hashlib.sha256(original).hexdigest() != digest:
            raise RuntimeError(f'Upstream source changed: {relative}')
        patched = transform(original.decode()).encode()
        if path.read_bytes() not in (original, patched):
            raise RuntimeError(f'Unexpected local edits: {relative}')
        changes.append((path, patched))
    helper = models / 'Qwen3TTS/EchoVoiceQwenSpeakerFeatures.swift'
    authored = (ROOT / 'model-fixes/QwenSpeakerFeatures.swift').read_bytes()
    if helper.exists() and helper.read_bytes() != authored:
        raise RuntimeError('Unexpected local edits to Qwen feature helper')
    changes.append((helper, authored))
    for path, content in changes:
        if path.exists():
            path.chmod(path.stat().st_mode | 0o200)
        path.write_bytes(content)
    print('Verified Qwen frontend and Chatterbox integration fixes applied.')

if __name__ == '__main__':
    patch(Path(sys.argv[1]))
