# Decisions

## Native and local

- A native SwiftUI app for macOS 26 on Apple Silicon. No Terminal, no local web server, no Python.
- Speech is made by Breeze TTS 2 through mlx-audio-swift on MLX. Its MLX checkpoints (8-bit by default; full precision and 4-bit as options) are downloaded once from Hugging Face into `~/Library/Application Support/EchoVoice/Models`, without a second copy in a shared cache. After that EchoVoice works offline.
- Voices, scripts, history and recordings never leave the Mac. No accounts, analytics or uploads.
- The model is loaded on demand and released after a configurable idle time (default 10 minutes), so it doesn't hold memory between uses.

## Voices

- A voice is one clip plus its exact transcript, which Breeze needs for cloning. Clips are converted to mono 24 kHz, silence is trimmed, quiet clips are raised, and clips must be 3 to 60 seconds of speech (8 to 25 recommended). Silent clips are refused; distorted or long clips get a note.
- Transcripts are written by Apple's on-device speech recognition (SpeechTranscriber) and always shown for checking before saving.
- Deleting a voice moves its clip to the Trash. Recordings made with it are kept.

## Recordings

- Scripts of any length (up to 50,000 characters) are split at sentence boundaries into parts of about 400 characters, far below the model's 750-step limit per pass (about a minute of speech). Long sentences break at commas, then spaces. A part that still reaches the limit is reported as possibly cut off.
- Each part's seed is derived from the recording's seed, so Same Take repeats a recording and New Take varies it.
- Parts are joined with 0.25 s pauses between sentences and 0.6 s between paragraphs, and saved as 16-bit WAV through a temporary file, so a half-written file is never left behind.

## Build and distribution

- MLX's Metal code compiles only in Xcode, so CI builds with `xcodebuild` (with the Metal toolchain) instead of `swift build`, and the packaging script verifies that MLX's `default.metallib` is inside the app.
- Dependencies are pinned: mlx-audio-swift to a tested commit, and MLX, Hugging Face and transformers packages to exact versions.
- CI tests, packages and smoke-launches the app. Releases attach the tested ZIP and its checksum from the main-branch CI build.
