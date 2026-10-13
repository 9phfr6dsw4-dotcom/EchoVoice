import EchoVoiceCore
import SwiftUI

/// Every recording, newest first: play it, find it, make it again, or reuse its script.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var deleting: HistoryItem?
    @State private var confirmClear = false

    var body: some View {
        let items = model.library.searchHistory(query)
        Page(title: "History", subtitle: "Everything you've made. Recordings are saved as WAV files in \(model.outputFolder.lastPathComponent).") {
            HStack(spacing: 12) {
                TextField("Search scripts and voices", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                Spacer()
                Button("Open Folder", systemImage: "folder") { model.showOutputFolder() }
                Button("Clear History…") { confirmClear = true }
                    .disabled(model.library.history.isEmpty)
            }
            if model.library.history.isEmpty {
                ContentUnavailableView("No recordings yet", systemImage: "waveform",
                                       description: Text("Recordings you make on the Write page show up here."))
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else if items.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(items) { item in
                        HistoryRow(item: item, delete: { deleting = item })
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
        .confirmationDialog("Clear the History list?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { model.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the list is cleared. The recordings stay in your folder.")
        }
    }
}

struct HistoryRow: View {
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
                    .help("Make it again with the same settings and seed (\(item.seed)). Usually very close to the original.")
                Button("New Take") { model.regenerate(item, sameTake: false) }
                    .help("Make it again with a fresh seed for a different reading.")
                Button("Use Script") { model.useScript(item) }
                    .help("Put this script on the Write page to edit it.")
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
