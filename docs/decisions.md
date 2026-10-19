# Decisions

## Native and local

- A native SwiftUI app for macOS 26 on Apple Silicon. No Terminal, no local web server, no Python.
- Speech is made by Qwen3-TTS 1.7B Base (8-bit, `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit`) through mlx-audio-swift on MLX. Chatterbox Turbo FP16 (`mlx-community/chatterbox-turbo-fp16`) is also available for English cloning. Qwen remains the upgrade default; selection is saved and new recordings remember their model. Only one engine is loaded at a time. It is downloaded once from Hugging Face into `~/Library/Application Support/EchoVoice/Models`, without a second copy in a shared cache. After that EchoVoice works offline.
- Voices, scripts, the Recordings list and audio files never leave the Mac. No accounts, analytics or uploads.
- The model is loaded on demand and released after a configurable idle time (default 10 minutes), so it doesn't hold memory between uses.

## Voices

- A voice is one clip plus its exact transcript, which Qwen3-TTS needs for cloning; the transcript is optional when saving a voice for Chatterbox. Chatterbox requires more than five seconds of reference speech. Clips are converted to mono 24 kHz, silence is trimmed, quiet clips are raised, and clips must be 3 to 60 seconds of speech (8 to 25 recommended). Silent clips are refused; distorted or long clips get a note.
- Transcripts are written by Apple's on-device speech recognition (SpeechTranscriber) and always shown for checking before saving.
- Deleting a voice moves its clip to the Trash. Recordings made with it are kept.

## Generating audio

- Scripts of any length (up to 50,000 characters) are split at sentence boundaries into parts of about 400 characters, far below the 750-step limit per pass we set (12.5 steps per second, about a minute of speech). Long sentences break at commas, then spaces. A part that still reaches the limit is reported as possibly cut off.
- Each part's seed is derived from the recording's seed, so Same Take repeats a recording and New Take varies it.
- The script stays in place after generating, so it can be tweaked and generated again. **New Script** clears the script (keeping the voice, the last audio and the Recordings list) and offers Undo, which restores it.
- Parts are joined with 0.25 s pauses between sentences and 0.6 s between paragraphs, and saved as 16-bit WAV through a temporary file, so a half-written file is never left behind.

## Wording

- The pages are Generate, Voices, Recordings and Settings. Buttons say exactly what they do: Generate Audio, New Script, Use voice.
- Privacy is stated once in full in Settings; other pages show a short “Processed on your Mac” note.
- There is no delivery style: Qwen3-TTS Base ignores style instructions when it clones a voice from a clip. Recordings made with the old Breeze model keep their saved style text, shown in Recordings; the old per-recording `quality` field is ignored when a library loads.
- Breeze model files from earlier versions are not deleted; they can be removed from `~/Library/Application Support/EchoVoice/Models/mlx-audio`.

## Pearl Editorial design

- A deliberate light palette of warm ivory, deep teal, and ink, with Baskerville for headings and scripts and system text for controls.
- Top navigation keeps the original four destinations and keyboard shortcuts. The content column follows the window width up to a reading limit of 1680 points, and the Generate page grows to the height of the window: the script editor takes the spare room, and the voice column widens a little. At the standard window size nothing changes; below the minimum height the page scrolls. The pure sizing rules live in `PageLayout` and are unit-tested.
- The voice picker sits beside the script. Playback, regeneration, drag-out, deletion, and New Script with Undo keep their original behavior.
- CI captures the actual packaged SwiftUI screens at 1180×840, 900×620 and 2560×1440 (a full-screen stand-in) with temporary fictional fixtures, and fails if the script editor does not grow at the large size. Its capture entry point requires GitHub Actions; it does not access the normal library or download the voice model.

## App icon

- The icon is an Icon Composer file (`Resources/AppIcon.icon`: an ivory gradient background and a teal E monogram layer). The packaging script compiles it with `actool` into `Assets.car` and sets `CFBundleIconName`. On newer macOS versions an app with only a classic `.icns` can be shown shrunk onto a grey plate in the Dock.
- The classic `AppIcon.icns`, made from `Resources/AppIcon-1024.png`, is still bundled with `CFBundleIconFile` as a fallback.
- `actool` can exit successfully without compiling the icon, so the script checks that `Assets.car` exists and names `AppIcon`, in the app and in the ZIP.

Artwork can be regenerated with `swift Scripts/DrawPearlIcon.swift .`; it uses the macOS Baskerville glyph outline and writes the modern foreground, classic fallback, and README image.

## Build and distribution

- MLX's Metal code compiles only in Xcode, so CI builds with `xcodebuild` (with the Metal toolchain) instead of `swift build`, and the packaging script verifies that MLX's `default.metallib` is inside the app.
- Dependencies are pinned: mlx-audio-swift to a tested commit, and MLX, Hugging Face and transformers packages to exact versions.
- CI tests, packages and smoke-launches the app. Releases attach the tested ZIP and its checksum from the main-branch CI build.


- Since 0.5.0, `Scripts/prepare-models.sh` resolves the exact pinned MLX dependency and applies hash-checked, idempotent fixes. Qwen uses a dedicated speaker frontend matching the official Slaney log-magnitude formula, without changing DSP shared with other models. Its reference cache keeps the input alive, and the app prepares conditioning once per recording. CPU tests compare the actual patched function against synthetic librosa data.
- Chatterbox Turbo downloads both its main checkpoint and S3TokenizerV2 into the app model folder. The patched factory loads that tokenizer locally and propagates errors instead of silently falling back to default voice tokens. Its request token cap is honored, actual speech tokens are reported, and its 1,500-step budget reflects 25 tokens per second. Qwen retains its 750-step budget.
- Libraries predating model selection decode with an absent model field. Existing audio remains playable; legacy regeneration uses Qwen, and corrected conditioning can change its sound. Reference-clip sample rate remains 24 kHz for both engines.
