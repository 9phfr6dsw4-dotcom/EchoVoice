# Decisions

## Native and local

- A native SwiftUI app for macOS 26 on Apple Silicon. No Terminal, no local web server, no Python.
- Speech is made by Breeze TTS 2 through mlx-audio-swift on MLX. Its MLX checkpoints (8-bit by default; full precision and 4-bit as options) are downloaded once from Hugging Face into `~/Library/Application Support/EchoVoice/Models`, without a second copy in a shared cache. After that EchoVoice works offline.
- Voices, scripts, the Recordings list and audio files never leave the Mac. No accounts, analytics or uploads.
- The model is loaded on demand and released after a configurable idle time (default 10 minutes), so it doesn't hold memory between uses.

## Voices

- A voice is one clip plus its exact transcript, which Breeze needs for cloning. Clips are converted to mono 24 kHz, silence is trimmed, quiet clips are raised, and clips must be 3 to 60 seconds of speech (8 to 25 recommended). Silent clips are refused; distorted or long clips get a note.
- Transcripts are written by Apple's on-device speech recognition (SpeechTranscriber) and always shown for checking before saving.
- Deleting a voice moves its clip to the Trash. Recordings made with it are kept.

## Generating audio

- Scripts of any length (up to 50,000 characters) are split at sentence boundaries into parts of about 400 characters, far below the model's 750-step limit per pass (about a minute of speech). Long sentences break at commas, then spaces. A part that still reaches the limit is reported as possibly cut off.
- Each part's seed is derived from the recording's seed, so Same Take repeats a recording and New Take varies it.
- The script stays in place after generating, so it can be tweaked and generated again. **New Script** clears the script and delivery style (keeping the voice, the last audio and the Recordings list) and offers Undo, which restores both fields.
- Parts are joined with 0.25 s pauses between sentences and 0.6 s between paragraphs, and saved as 16-bit WAV through a temporary file, so a half-written file is never left behind.

## Wording

- The pages are Generate, Voices, Recordings and Settings. Buttons say exactly what they do: Generate Audio, New Script, Use voice.
- Privacy is stated once in full in Settings; other pages show a short “Processed on your Mac” note.
- Qualities are named for what you get: Balanced (recommended, 8-bit), Best quality (full precision) and Fastest (4-bit). The saved setting keeps its old internal values, so existing settings carry over.

## Pearl Editorial design

- A deliberate light palette of warm ivory, deep teal, and ink, with Baskerville for headings and scripts and system text for controls.
- Top navigation keeps the original four destinations and keyboard shortcuts. Content has a maximum reading width instead of stretching across a large display.
- The voice picker and free-form delivery field sit beside the script. Playback, regeneration, drag-out, deletion, and New Script with Undo keep their original behavior. No saved-data schema or preference keys change.
- CI captures the actual packaged SwiftUI screens at 1180×840 and 900×620 with temporary fictional fixtures. Its capture entry point requires GitHub Actions; it does not access the normal library or download the voice model.

## App icon

- The icon is an Icon Composer file (`Resources/AppIcon.icon`: an ivory gradient background and a teal E monogram layer). The packaging script compiles it with `actool` into `Assets.car` and sets `CFBundleIconName`. On newer macOS versions an app with only a classic `.icns` can be shown shrunk onto a grey plate in the Dock.
- The classic `AppIcon.icns`, made from `Resources/AppIcon-1024.png`, is still bundled with `CFBundleIconFile` as a fallback.
- `actool` can exit successfully without compiling the icon, so the script checks that `Assets.car` exists and names `AppIcon`, in the app and in the ZIP.

Artwork can be regenerated with `swift Scripts/DrawPearlIcon.swift .`; it uses the macOS Baskerville glyph outline and writes the modern foreground, classic fallback, and README image.

## Build and distribution

- MLX's Metal code compiles only in Xcode, so CI builds with `xcodebuild` (with the Metal toolchain) instead of `swift build`, and the packaging script verifies that MLX's `default.metallib` is inside the app.
- Dependencies are pinned: mlx-audio-swift to a tested commit, and MLX, Hugging Face and transformers packages to exact versions.
- CI tests, packages and smoke-launches the app. Releases attach the tested ZIP and its checksum from the main-branch CI build.

