import EchoVoiceCore
import SwiftUI

/// Generate: pick a voice, write or paste a script, and turn it into audio.
struct GenerateView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var scriptFocused: Bool
    @Environment(\.windowWidth) private var windowWidth

    var body: some View {
        Page(title: "Every word, considered.", subtitle: "Your private voice studio. Turn a script into something worth hearing.", showsPrivacyFooter: false) {
            ModelBanner()
            if model.voices.isEmpty {
                noVoices
            } else {
                HStack(alignment: .top, spacing: 30) {
                    VStack(alignment: .leading, spacing: 26) {
                        voiceRow
                        Rectangle().fill(Theme.rule).frame(height: 1)
                        deliveryField
                    }
                    .frame(width: CGFloat(PageLayout.sideColumnWidth(forWindow: Double(windowWidth))), alignment: .topLeading)
                    .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 20) {
                        scriptField
                        actionRow
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        return VStack(alignment: .leading, spacing: 14) {
            Text("THE VOICE")
                .font(.system(size: 11, weight: .medium))
                .tracking(1.6)
                .foregroundStyle(Theme.muted)
            if let voice = model.selectedVoice {
                VoiceInitial(name: voice.name, size: 52)
                Text(voice.name)
                    .font(Theme.editorial(24))
                    .fixedSize(horizontal: false, vertical: true)
                Caption("Your saved voice, ready to speak.")
            }
            Picker("Voice", selection: $model.selectedVoiceID) {
                Text("Choose a voice").tag(Optional<UUID>.none)
                ForEach(model.voices) { voice in
                    Text(voice.name).tag(Optional(voice.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .disabled(model.isModelBusy)
            Divider()
            Text(VoiceModel.breeze.title)
                .font(.callout.weight(.medium))
            Caption("Uses your clip and its exact words.")
        }
    }

    private var scriptField: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SCRIPT")
                    .tracking(1.5)
                Spacer()
                Text(scriptSummary)
                    .monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 24)
            .padding(.vertical, 17)
            Rectangle().fill(Theme.rule.opacity(0.6)).frame(height: 1)
            TextEditor(text: $model.script)
                .font(Theme.editorial(23))
                .lineSpacing(7)
                .foregroundStyle(Theme.ink)
                .focused($scriptFocused)
                .scrollContentBackground(.hidden)
                .padding(20)
                .frame(minHeight: 290, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if model.script.isEmpty {
                        Text("Begin your next story…")
                            .foregroundStyle(Theme.muted)
                            .font(Theme.editorial(23))
                            .padding(.horizontal, 25)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Script")
                .disabled(model.isGenerating)
            Rectangle().fill(Theme.rule.opacity(0.6)).frame(height: 1)
            Caption("Paragraph breaks add a longer pause.")
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.rule.opacity(0.6)))
        .shadow(color: Theme.ink.opacity(0.035), radius: 16, y: 5)
    }

    private var deliveryField: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Delivery style")
                    .font(.system(size: 12, weight: .medium))
                Text("Optional")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            TextField("Delivery style", text: $model.direction, prompt: Text("e.g. calm, upbeat"))
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
                    .buttonStyle(PearlPrimaryButtonStyle())
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
                HStack(alignment: .top, spacing: 12) {
                    if progress.parts > 1, progress.part > 0 {
                        ProgressView(value: Double(progress.part - 1), total: Double(progress.parts))
                            .frame(maxWidth: 100)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(progress.stage)
                        if let left = progress.secondsLeft {
                            Text("About \(TimeText.clock(left)) left")
                                .foregroundStyle(Theme.muted)
                                .monospacedDigit()
                        }
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
                Button("New Script", systemImage: "plus") {
                    model.newScript()
                    scriptFocused = true
                }
                .disabled(!canStartNewScript)
                .help("Clear the script and delivery style. Your voice, audio and recordings stay as they are.")
                Spacer()
                Button {
                    model.generate()
                } label: {
                    Label("Generate Audio", systemImage: "waveform")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(PearlPrimaryButtonStyle())
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.selectedVoice == nil || model.isDownloading || model.isManagingModel)
                .help("Generate Audio (⌘↩)")
                if model.isDownloading {
                    Caption("Available when the download finishes.")
                }
            }
        }
    }

    private var footerRow: some View {
        HStack {
            PrivacyFooter()
            Spacer()
            Text("Saved automatically to Recordings")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
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
                        Caption("\(model.selectedModel.title) runs on this Mac. Download it once, then work offline. The download also starts automatically when you first generate audio.")
                    }
                    Spacer()
                    Button("Download Now") { model.downloadModel() }
                        .buttonStyle(PearlPrimaryButtonStyle())
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

