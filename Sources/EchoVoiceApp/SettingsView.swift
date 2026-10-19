import AppKit
import EchoVoiceCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(UpdateController.self) private var updates

    var body: some View {
        @Bindable var model = model
        Page(title: "Thoughtful settings", subtitle: "A few details, just the way you like them. Everything stays on your Mac.") {
            GroupBox("Voice model") {
                VStack(alignment: .leading, spacing: 20) {
                    modelRow
                    Button("Open Model Downloads in Finder") {
                        NSWorkspace.shared.open(model.engine.modelsFolder.appendingPathComponent("mlx-audio"))
                    }
                    Caption("To reclaim space from previous versions, quit EchoVoice and move the Qwen3-TTS, chatterbox-turbo and S3TokenizerV2 folders to the Trash. Keep the Breeze folder. Empty the Trash to free the space.")
                    if case .downloading(let fraction) = model.modelState {
                        DownloadProgressRow(fraction: fraction)
                    }
                    Caption("Downloaded once, a few GB. After that EchoVoice works offline.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            GroupBox("Recordings") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(model.outputFolder.path, systemImage: "folder")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Change…") { model.chooseOutputFolder() }
                        Button("Open") { model.showOutputFolder() }
                    }
                    Toggle("Play new audio when it's ready", isOn: $model.playWhenDone)
                    Caption("Audio is saved as 24 kHz WAV files, named with the voice and the time it was generated.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            GroupBox("Memory") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Free up memory after", selection: $model.unloadAfterMinutes) {
                        Text("5 minutes idle").tag(5)
                        Text("10 minutes idle").tag(10)
                        Text("30 minutes idle").tag(30)
                        Text("Never").tag(0)
                    }
                    .frame(maxWidth: 420)
                    HStack {
                        Text(memoryStatus)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Free up memory now") { model.freeMemory() }
                            .disabled(model.modelState != .ready || model.isModelBusy)
                    }
                    Caption("Freeing memory unloads the voice model. It loads again, in a few seconds, before your next generation.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            GroupBox("Updates") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updates.automaticallyChecks },
                        set: { updates.setAutomaticallyChecks($0) }
                    ))
                    Caption("EchoVoice looks for a new version when it starts and then every hour.")
                    Toggle("Download and install updates automatically", isOn: Binding(
                        get: { updates.automaticallyInstalls },
                        set: { updates.setAutomaticallyInstalls($0) }
                    ))
                    .disabled(!updates.automaticallyChecks)
                    Caption("EchoVoice installs a new version and reopens by itself, once no voice is being made, downloaded, recorded or transcribed. Your voices, scripts, recordings and settings stay as they are.")
                    HStack {
                        Text(lastUpdateCheckText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Check for Updates…") { updates.checkForUpdates() }
                            .disabled(!updates.canCheckForUpdates)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            GroupBox("Privacy") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Everything is processed on this Mac. Your voices, scripts and audio are never uploaded.", systemImage: "lock.shield")
                        .fixedSize(horizontal: false, vertical: true)
                    Label("The internet is used to download the voice model and to check GitHub for a new version of EchoVoice.", systemImage: "arrow.down.circle")
                        .fixedSize(horizontal: false, vertical: true)
                    Label("No account, no analytics, no tracking.", systemImage: "eye.slash")
                        .fixedSize(horizontal: false, vertical: true)
                    Caption("Breeze TTS 2 runs with Apple's MLX. Its model weights are for personal, non-commercial use only.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
    }

    private var lastUpdateCheckText: String {
        guard let date = updates.lastCheckDate else { return "Not checked for updates yet." }
        return "Last checked \(date.formatted(date: .abbreviated, time: .shortened))."
    }

    private var memoryStatus: String {
        switch model.modelState {
        case .ready: return "The voice model is loaded."
        case .loading: return "Loading the voice model…"
        case .downloading: return "Downloading the voice model…"
        case .idle, .notDownloaded: return "The voice model isn't using any memory."
        }
    }

    private var modelRow: some View {
        let downloaded = model.isModelDownloaded
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(model.selectedModel.title)
                        .font(.system(size: 14, weight: .medium))
                    if downloaded {
                        Text("On this Mac")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.success.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.success)
                    }
                }
                Caption(model.selectedModel.detail)
            }
            Spacer()
            if !downloaded {
                Button("Download") { model.downloadModel() }
                    .disabled(model.isModelBusy)
            } else {
                Button("Remove") { model.removeModel() }
                    .disabled(model.isModelBusy)
                    .help("Move this download to the Trash to free disk space.")
            }
        }
        .controlSize(.small)
        .contentShape(Rectangle())
    }
}
