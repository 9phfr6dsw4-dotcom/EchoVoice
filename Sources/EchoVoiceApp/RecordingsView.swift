import EchoVoiceCore
import SwiftUI

/// Every recording, newest first: play it, find it, generate it again, or reuse its script.
struct RecordingsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var deleting: HistoryItem?
    @State private var confirmClear = false

    var body: some View {
        let items = model.library.searchHistory(query)
        Page(title: "Recordings", subtitle: "Your generated audio, saved automatically.") {
            HStack(spacing: 12) {
                TextField("Search recordings", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                Spacer()
                Button("Open Folder", systemImage: "folder") { model.showOutputFolder() }
                Button("Clear List…") { confirmClear = true }
                    .disabled(model.library.history.isEmpty)
            }
            if model.library.history.isEmpty {
                ContentUnavailableView {
                    Label("No recordings yet", systemImage: "waveform")
                } description: {
                    Text("Generate your first audio to get started.")
                } actions: {
                    Button("Go to Generate") { model.section = .generate }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            } else if items.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(items) { item in
                        RecordingRow(item: item, delete: { deleting = item })
                    }
                }
            }
        }
        .confirmationDialog("Move “\(deleting?.fileName ?? "")” to the Trash?", isPresented: Binding(
            get: { deleting != nil },
            set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                if let item = deleting { model.deleteRecording(item) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        }
        .confirmationDialog("Clear the Recordings list?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear List", role: .destructive) { model.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the list is cleared. The audio files stay in \(model.outputFolder.lastPathComponent).")
        }
    }
}

struct RecordingRow: View {
    @Environment(AppModel.self) private var model
    let item: HistoryItem
    let delete: () -> Void

    var body: some View {
        let url = URL(fileURLWithPath: item.filePath)
        let exists = model.fileExists(item)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    model.playback.toggle(url)
                } label: {
                    Image(systemName: model.playback.isPlaying(url) ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(exists ? Theme.accent : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!exists)
                .accessibilityLabel(model.playback.isPlaying(url) ? "Pause" : "Play")
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.script)
                        .lineLimit(3)
                    HStack(spacing: 6) {
                        Text(item.voiceName)
                        Text("·")
                        Text(TimeText.clock(item.seconds)).monospacedDigit()
                        Text("·")
                        Text(DateText.medium(item.date))
                        if let direction = item.direction {
                            Text("·")
                            Text("“\(direction)”").italic()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if !exists {
                        WarningLabel(message: "The file was moved or deleted.")
                    } else if !item.cutOffParts.isEmpty {
                        WarningLabel(message: "May be cut off in part \(item.cutOffParts.map(String.init).joined(separator: ", ")).")
                    }
                }
                Spacer(minLength: 8)
            }
            if model.playback.currentURL == url {
                ProgressView(value: model.playback.progress)
            }
            HStack(spacing: 8) {
                Button("Same Take") { model.regenerate(item, sameTake: true) }
                    .help("Generate it again with the same settings and seed (\(item.seed)). Usually very close to the original.")
                Button("New Take") { model.regenerate(item, sameTake: false) }
                    .help("Generate it again with a fresh seed for a different reading.")
                Button("Use Script") { model.useScript(item) }
                    .help("Put this script on the Generate page to edit it.")
                Spacer()
                if exists {
                    Button("Show in Finder", systemImage: "folder") { model.reveal(item) }
                }
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Move this recording to the Trash")
            }
            .controlSize(.small)
            .disabled(model.isGenerating)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .draggable(url)
    }
}
