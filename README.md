<p align="center">
  <img src="docs/images/echovoice-icon.png" width="88" alt="EchoVoice app icon">
</p>

<h1 align="center">EchoVoice</h1>

<p align="center">Text to speech in your own voice, on your Mac. Paste any script, pick a voice you saved, and generate audio, with no cloud and no Terminal.</p>

<p align="center"><a href="https://github.com/9phfr6dsw4-dotcom/EchoVoice/releases/latest"><strong>Download the latest release</strong></a> · macOS 26+ · Apple Silicon</p>

<p align="center">
  <a href="https://github.com/9phfr6dsw4-dotcom/EchoVoice/releases/latest"><img src="https://img.shields.io/github/v/release/9phfr6dsw4-dotcom/EchoVoice?display_name=tag" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple" alt="macOS 26 or later">
  <a href="https://github.com/9phfr6dsw4-dotcom/EchoVoice/actions/workflows/macos-ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/9phfr6dsw4-dotcom/EchoVoice/macos-ci.yml?branch=main&amp;label=macOS%20CI" alt="macOS CI status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
</p>

## Features

- **Any length.** Paste a sentence or a whole article. Long scripts are split at sentence boundaries, spoken part by part and joined into one file, with slightly longer pauses between paragraphs.
- **Your voices.** Save as many voices as you like from a short clip: record one with your Mac's microphone, or import WAV, M4A, MP3 or AIFF. EchoVoice trims the silence, checks the clip, and writes down its words with Apple's on-device speech recognition. You just check them.
- **New Script.** Clear the script in one click to start the next one, keeping your voice. Changed your mind? **Undo** brings it back.
- **Recordings.** Every generated audio file with its script, voice and date. Play it, find it in Finder, drag it into another app, reuse the script, or make it again: **Same Take** repeats it with the same seed, **New Take** gives a fresh reading.
- **Saved automatically** as WAV files in Downloads → EchoVoice, or a folder you choose.
- **Easy on your Mac.** The model loads when you need it and releases its memory after a few idle minutes.
- **Private.** Everything runs on your Mac. The internet is used only once, to download the voice model.

EchoVoice uses [Qwen3-TTS](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-Base) 1.7B Base (8-bit), run on Apple Silicon with MLX through [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift). Check the model card for its license before you distribute or sell anything built on it.

## Pearl Editorial

Warm ivory surfaces, a deep teal accent, editorial typography, and top navigation give EchoVoice a focused workspace. The script editor sits beside its voice controls; Voices, Recordings, and Settings share the same design. Existing voices, audio, scripts, settings, and models carry over.

Native captures of all four screens at the default, minimum and a large full-screen window size are produced by CI using an isolated fictional library. The `EchoVoice-design-captures` artifact is attached to each CI run.

## Install

1. Download `EchoVoice.zip` from the [latest release](https://github.com/9phfr6dsw4-dotcom/EchoVoice/releases/latest) and unzip it.
2. Drag **EchoVoice** into **Applications** (choose **Replace** when updating).
3. Open it. If macOS blocks it, open **System Settings → Privacy & Security** and choose **Open Anyway**. (Builds are ad-hoc signed, so macOS treats every new build as a new app.)
4. The first time you generate audio, the voice model downloads once (a few GB). You can also start the download from the Generate page or Settings.

You need an Apple Silicon Mac with macOS 26. 16 GB of memory is comfortable.

## How it works

1. **A voice** is a clip of one person speaking (8 to 25 seconds is ideal, 3 to 60 works) plus the exact words they say. The clip is stored as a 24 kHz WAV in `~/Library/Application Support/EchoVoice/Voices`.
2. **Generating audio** splits your script into parts of about 25 seconds of speech each. Each part is spoken by Qwen3-TTS in the chosen voice, with its own seed derived from the recording's seed, so a whole recording can be generated again the same way. If a part ever reaches the model's length limit, EchoVoice says so.
3. **The parts are joined** with short pauses and saved as a 16-bit WAV file. The Recordings list is kept in `~/Library/Application Support/EchoVoice/library.json`.

The voice model is stored in `~/Library/Application Support/EchoVoice/Models`. Remove the model in Settings to free the space.

## Building

You need macOS 26 and Xcode 26 with the Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`). MLX's GPU code is compiled by Xcode, so the app is built with `xcodebuild` rather than `swift build`:

```bash
bash Scripts/package-app.sh      # build dist/EchoVoice.app and dist/EchoVoice.zip
bash Scripts/smoke-test.sh       # launch the packaged app from a clean folder
```

- `Sources/EchoVoiceCore`: script splitting, WAV writing, clip checks, word counts, the voice library and the Recordings list. No dependencies; unit-tested.
- `Sources/EchoVoiceApp`: the SwiftUI app, recording and transcription, and the Qwen3-TTS engine.
- `Tests/EchoVoiceTests`: tests for the core.
- `Resources/AppIcon.icon`: the app icon in Icon Composer format, compiled into `Assets.car` by the packaging script. `Resources/AppIcon-1024.png` is the classic `.icns` fallback.

## License

MIT. See [LICENSE](LICENSE). The Qwen3-TTS weights have their own license.

