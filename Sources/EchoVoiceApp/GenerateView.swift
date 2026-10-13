import EchoVoiceCore
import SwiftUI

/// Generate: pick a voice, write or paste a script, optionally describe the delivery, and turn it
/// into audio.
struct GenerateView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var scriptFocused: Bool

    var body: some View {
        Page(title: "Generate", subtitle: "Turn your script into audio.", showsPrivacyFooter: false) {
            ModelBanner()
            if model.voices.isEmpty {
                noVoices
            } else {
                GroupBox {
                    VStack(alignment: .leading, spacing: 18) {
                        voiceRow
                        scriptField
                        deliveryField
                        actionRow
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                }
            }
            footerRow
            if let item = model.lastRecording {
                LastRecordingCard(item: item)
            }
        }
    }

    private var voiceRow: some View {
        @Bindable var model = model
        return HStack(spacing: 12) {
            Text("Voice")
                .foregroundStyle(.secondary)
            Picker("Voice", selection: $model.selectedVoiceID) {
                ForEach(model.voices) { voice in
                    Text(voice.name).tag(Optional(voice.id))
                }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(model.isGenerating)
            Spacer()
        }
    }

    private var scriptField: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Script")
                    .font(.headline)
                Spacer()
                Text(scriptSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            TextEditor(text: $model.script)
                .font(.system(size: 16))
                .focused($scriptFocused)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 220)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))
                .overlay(alignment: .topLeading) {
                    if model.script.isEmpty {
                        Text("Type or paste your script…")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 16))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .disabled(model.isGenerating)
            Caption("Paragraph breaks add a longer pause.")
        }
    }

    private var deliveryField: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Delivery style")
                    .font(.headline)
                Text("Optional")
                    .foregroundStyle(.secondary)
            }
            TextField("Delivery style", text: $model.direction, prompt: Text("e.g. calm, upbeat, conversational"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .disabled(model.isGenerating)
            Caption("Adding a style takes about twice as long to generate.")
        }
    }

    private var noVoices: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Add a voice to get started", systemImage: "person.wave.2")
                    .font(.headline)
                Caption("Record a short clip or import one. EchoVoice writes down the words for you.")
                Button("Add Voice…", systemImage: "plus") { model.section = .voices }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    /// "15 words", plus the number of parts when a long script is made in several.
    private var scriptSummary: String {
        let words = ScriptStats.wordLabel(model.script)
        guard !words.isEmpty else { return "" }
        let parts = ScriptSplitter.split(model.script).count
        return parts > 1 ? "\(words) · \(parts) parts" : words
    }

    private var canStartNewScript: Bool {
        !model.isGenerating && !(model.script.isEmpty && model.direction.isEmpty)
    }

    @ViewBuilder
    private var actionRow: some View {
        if let progress = model.progress {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    if progress.parts > 1, progress.part > 0 {
                        ProgressView(value: Double(progress.part - 1), total: Double(progress.parts))
                            .frame(maxWidth: 260)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(progress.stage)
                    if let left = progress.secondsLeft {
                        Text("About \(TimeText.clock(left)) left")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    Button("Stop", systemImage: "stop.fill") { model.stop() }
                        .keyboardShortcut(".", modifiers: .command)
                }
                if case .downloading(let fraction) = model.modelState {
                    DownloadProgressRow(fraction: fraction)
                }
            }
        } else {
            HStack(spacing: 12) {
                Button {
                    model.generate()
                } label: {
                    Label("Generate Audio", systemImage: "waveform")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.selectedVoice == nil || model.isDownloading)
                .help("Generate Audio (⌘↩)")
                if model.isDownloading {
                    Caption("Available when the download finishes.")
                }
                Spacer()
                Button("New Script") {
                    model.newScript()
                    scriptFocused = true
                }
                .controlSize(.large)
                .disabled(!canStartNewScript)
                .help("Clear the script and delivery style. Your voice, audio and recordings stay as they are.")
            }
        }
    }

    private var footerRow: some View {
        HStack {
            PrivacyFooter()
            Spacer()
            Text("Audio saves to Recordings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// The model's status, shown until it's ready to use.
struct ModelBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.modelState {
        case .notDownloaded where !model.isGenerating:
            GroupBox {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("One-time download")
                            .font(.headline)
                        Caption("EchoVoice runs the Breeze TTS 2 voice model on this Mac. It's downloaded once (\(model.quality.shortTitle), a few GB); after that, EchoVoice works offline. It also starts automatically when you first generate audio.")
                    }
                    Spacer()
                    Button("Download Now") { model.downloadModel() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            }
        case .downloading(let fraction) where !model.isGenerating:
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    DownloadProgressRow(fraction: fraction)
                    HStack {
                        Caption("You can keep using EchoVoice. Large files can take a while; the download continues if you switch pages.")
                        Spacer()
                        Button("Stop Download") { model.cancelDownload() }
                    }
                }
                .padding(.vertical, 4)
            }
        default:
            EmptyView()
        }
    }
}

struct DownloadProgressRow: View {
    let fraction: Double

    var body: some View {
        HStack(spacing: 10) {
            ProgressView(value: fraction)
                .frame(maxWidth: 320)
            Text("Downloading the voice model… \(Int((fraction * 100).rounded()))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// The most recent recording, ready to play, find or drag into another app.
struct LastRecordingCard: View {
    @Environment(AppModel.self) private var model
    let item: HistoryItem

    var body: some View {
        let url = URL(fileURLWithPath: item.filePath)
        GroupBox("Latest recording") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Button {
                        model.playback.toggle(url)
                    } label: {
                        Image(systemName: model.playback.isPlaying(url) ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.fileExists(item))
                    .accessibilityLabel(model.playback.isPlaying(url) ? "Pause" : "Play")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.fileName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(item.voiceName) · \(TimeText.clock(item.seconds)) · made in \(TimeText.clock(item.generationSeconds))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Show in Finder", systemImage: "folder") { model.reveal(item) }
                }
                if model.playback.currentURL == url {
                    ProgressView(value: model.playback.progress)
                }
                if !item.cutOffParts.isEmpty {
                    WarningLabel(message: "Part \(item.cutOffParts.map(String.init).joined(separator: ", ")) reached the model's length limit and may be cut off. Try a New Take from Recordings, or add a sentence break there.")
                }
                if !model.fileExists(item) {
                    WarningLabel(message: "This file was moved or deleted.")
                } else {
                    Caption("Drag the file name into another app, or find it in \(model.outputFolder.lastPathComponent).")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .draggable(url)
        }
    }
}
