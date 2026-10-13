import EchoVoiceCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Page(title: "Settings", subtitle: "Quality, where recordings go, and how EchoVoice uses your Mac's memory.") {
            GroupBox("Voice model: Breeze TTS 2") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ModelQuality.allCases) { quality in
                        qualityRow(quality)
                    }
                    if case .downloading(let fraction) = model.modelState {
                        DownloadProgressRow(fraction: fraction)
                    }
                    Caption("Changing quality applies to your next recording. A quality that isn't on this Mac yet is downloaded once.")
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
                    Toggle("Play each recording when it's finished", isOn: $model.playWhenDone)
                    Caption("Recordings are 24 kHz WAV files, named with the voice and the time they were made.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            GroupBox("Memory") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Release the model's memory after", selection: $model.unloadAfterMinutes) {
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
                        Button("Release Memory Now") { model.freeMemory() }
                            .disabled(model.modelState != .ready || model.isGenerating)
                    }
                    Caption("While loaded, the model keeps your next recording quick. Released, it uses no memory and loads again (a few seconds) when needed.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            GroupBox("About") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("EchoVoice runs Breeze TTS 2 by BreezeBlue entirely on this Mac with Apple's MLX. Breeze TTS 2 is licensed for personal, non-commercial use; its model card has the details.")
                        .fixedSize(horizontal: false, vertical: true)
                    Caption("No account, no cloud, no tracking. The internet is used only to download the model.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
    }

    private var memoryStatus: String {
        switch model.modelState {
        case .ready: return "The voice model is loaded."
        case .loading: return "Loading the voice model…"
        case .downloading: return "Downloading the voice model…"
        case .idle, .notDownloaded: return "The voice model isn't using any memory."
        }
    }

    private func qualityRow(_ quality: ModelQuality) -> some View {
        let downloaded = model.isDownloaded(quality)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.quality == quality ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(model.quality == quality ? Theme.accent : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(quality.title)
                        .font(.headline)
                    if downloaded {
                        Text("On this Mac")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.success.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.success)
                    }
                }
                Caption(quality.detail)
            }
            Spacer()
            if model.quality != quality {
                Button("Use") { model.quality = quality }
                    .disabled(model.isGenerating || model.isDownloading)
            } else if !downloaded {
                Button("Download") { model.downloadModel() }
                    .disabled(model.isGenerating || model.isDownloading)
            }
            if downloaded {
                Button("Remove") { model.removeModel(quality) }
                    .disabled(model.isGenerating || model.isDownloading)
                    .help("Move this download to the Trash to free disk space.")
            }
        }
        .controlSize(.small)
        .contentShape(Rectangle())
    }
}
