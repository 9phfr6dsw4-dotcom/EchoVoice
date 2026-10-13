import EchoVoiceCore
import SwiftUI
import UniformTypeIdentifiers

/// Every saved voice: listen to its clip, fix its words, rename or delete it.
struct VoicesView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAdd = false
    @State private var editing: Voice?
    @State private var deleting: Voice?

    var body: some View {
        Page(title: "Voices", subtitle: "A voice is a short clip of someone speaking and the exact words they say in it.") {
            HStack {
                Button("Add Voice…", systemImage: "plus") { showingAdd = true }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Caption("\(model.voices.count) voice\(model.voices.count == 1 ? "" : "s")")
            }
            if model.voices.isEmpty {
                ContentUnavailableView("No voices yet", systemImage: "person.wave.2",
                                       description: Text("Add a voice by recording a short clip or importing one."))
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(spacing: 10) {
                    ForEach(model.voices) { voice in
                        VoiceRow(voice: voice, edit: { editing = voice }, delete: { deleting = voice })
                    }
                }
            }
            GroupBox("Tips for a good clip") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("One person, speaking naturally, in a quiet room with no music.", systemImage: "person")
                    Label("8 to 25 seconds is ideal. Anything from 3 to 60 seconds works.", systemImage: "timer")
                    Label("The words must match the clip exactly. EchoVoice writes them down; check them before saving.", systemImage: "text.quote")
                    Label("Breeze TTS 2 speaks English and Chinese.", systemImage: "globe")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddVoiceSheet()
                .environment(model)
        }
        .sheet(item: $editing) { voice in
            EditVoiceSheet(voice: voice)
                .environment(model)
        }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(
            get: { deleting != nil },
            set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Voice", role: .destructive) {
                if let voice = deleting { model.deleteVoice(voice.id) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Its clip goes to the Trash. Recordings made with it are kept.")
        }
    }
}

struct VoiceRow: View {
    @Environment(AppModel.self) private var model
    let voice: Voice
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        let clip = model.clipURL(for: voice)
        HStack(alignment: .top, spacing: 12) {
            Button {
                model.playback.toggle(clip)
            } label: {
                Image(systemName: model.playback.isPlaying(clip) ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play the clip of \(voice.name)")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(voice.name)
                        .font(.headline)
                    if model.selectedVoiceID == voice.id {
                        Text("Selected")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text("“\(voice.transcript)”")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Caption("\(TimeText.clock(voice.seconds)) clip · added \(DateText.medium(voice.created))")
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Button("Use") {
                    model.selectedVoiceID = voice.id
                    model.section = .write
                }
                HStack(spacing: 6) {
                    Button("Edit…", action: edit)
                    Button(role: .destructive, action: delete) {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete \(voice.name)")
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Record or import a clip, check it, get its words, name it, save it.
struct AddVoiceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = ClipRecorder()
    @State private var name = ""
    @State private var transcript = ""
    @State private var samples: [Float] = []
    @State private var previewURL: URL?
    @State private var check: ReferenceCheck.Result?
    @State private var problem: String?
    @State private var isPreparing = false
    @State private var isTranscribing = false
    @State private var importing = false
    /// True from Record until that recording has been handed to `use`.
    @State private var pendingRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a Voice")
                .font(.title2.weight(.semibold))
            clipSection
            if let check {
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(TimeText.clock(check.seconds)) of speech", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success)
                    ForEach(check.notes, id: \.self) { WarningLabel(message: $0) }
                }
            }
            if let problem {
                ErrorLabel(message: problem)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Exact words in the clip")
                        .font(.headline)
                    Spacer()
                    if isTranscribing {
                        ProgressView().controlSize(.small)
                        Caption("Writing down the words…")
                    } else if previewURL != nil {
                        Button("Write Down the Words Again") { transcribe() }
                            .controlSize(.small)
                    }
                }
                TextEditor(text: $transcript)
                    .font(.body)
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))
                Caption("Breeze copies a voice best when these words match the clip exactly. Listen once and fix anything that's off.")
            }
            TextField("Name", text: $name, prompt: Text("e.g. Jordan, or Jordan – calm"))
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    pendingRecording = false
                    recorder.stop()
                    model.playback.stop()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save Voice") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(samples.isEmpty || check == nil || isPreparing || recorder.isRecording)
            }
        }
        .padding(22)
        .frame(width: 560)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { use(url, fromRecording: false) }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in use(url, fromRecording: false) }
            }
            return true
        }
        .onChange(of: recorder.isRecording) { _, isRecording in
            // Also covers the automatic stop at 60 seconds, not only the Stop button.
            if !isRecording, pendingRecording, let url = recorder.fileURL {
                pendingRecording = false
                use(url, fromRecording: true)
            }
        }
        .onDisappear {
            pendingRecording = false
            recorder.stop()
        }
    }

    @ViewBuilder
    private var clipSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if recorder.isRecording {
                    HStack(spacing: 12) {
                        Image(systemName: "record.circle.fill")
                            .foregroundStyle(.red)
                        Text("Recording \(TimeText.clock(recorder.elapsed))")
                            .monospacedDigit()
                        ProgressView(value: recorder.level)
                            .frame(maxWidth: 160)
                        Spacer()
                        Button("Stop", systemImage: "stop.fill") { finishRecording() }
                            .buttonStyle(.borderedProminent)
                    }
                    Caption("Speak naturally, the way you normally talk. Recording stops by itself after 60 seconds.")
                } else if isPreparing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Getting the clip ready…")
                    }
                } else {
                    HStack(spacing: 10) {
                        Button(samples.isEmpty ? "Record" : "Record Again", systemImage: "mic.fill") { startRecording() }
                            .buttonStyle(.borderedProminent)
                        Button("Import a File…", systemImage: "square.and.arrow.down") { importing = true }
                        Spacer()
                        if let previewURL {
                            Button {
                                model.playback.toggle(previewURL)
                            } label: {
                                Label(model.playback.isPlaying(previewURL) ? "Pause" : "Listen", systemImage: model.playback.isPlaying(previewURL) ? "pause.fill" : "play.fill")
                            }
                        }
                    }
                    Caption("Record with your Mac's microphone, or import (or drop here) a recording such as WAV, M4A, MP3 or AIFF.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func startRecording() {
        problem = nil
        model.playback.stop()
        Task {
            do {
                try await recorder.start()
                pendingRecording = true
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    /// Stopping ends the recording; `onChange(of: recorder.isRecording)` then prepares the clip.
    private func finishRecording() {
        recorder.stop()
    }

    /// Turns a recording or imported file into a clean clip: mono, 24 kHz, silence trimmed,
    /// raised if very quiet. Then checks it and writes down its words.
    private func use(_ url: URL, fromRecording: Bool) {
        problem = nil
        check = nil
        isPreparing = true
        model.playback.stop()
        if !fromRecording, name.isEmpty {
            name = url.deletingPathExtension().lastPathComponent
        }
        let access = url.startAccessingSecurityScopedResource()
        Task {
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let rate = VoiceEngine.sampleRate
                let prepared = try await Task.detached(priority: .userInitiated) { () throws -> [Float] in
                    let raw = try AudioFileReader.monoSamples(from: url, sampleRate: rate)
                    return AudioTools.normalizedIfQuiet(AudioTools.trimSilence(raw, sampleRate: rate))
                }.value
                let result = try ReferenceCheck.check(prepared, sampleRate: rate)
                let preview = FileManager.default.temporaryDirectory.appendingPathComponent("EchoVoice-preview-\(UUID().uuidString).wav")
                try WAVFile.write(samples: prepared, sampleRate: rate, to: preview)
                samples = prepared
                check = result
                previewURL = preview
                isPreparing = false
                transcribe()
            } catch {
                samples = []
                previewURL = nil
                isPreparing = false
                problem = error.localizedDescription
            }
        }
    }

    private func transcribe() {
        guard let previewURL, !isTranscribing else { return }
        isTranscribing = true
        Task {
            do {
                transcript = try await ClipTranscriber.transcribe(previewURL)
            } catch {
                if transcript.isEmpty { problem = error.localizedDescription }
            }
            isTranscribing = false
        }
    }

    private func save() {
        do {
            let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Voice \(model.voices.count + 1)" : name
            try model.addVoice(name: finalName, transcript: transcript, samples: samples)
            model.playback.stop()
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// Rename a voice or correct the words of its clip.
struct EditVoiceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let voice: Voice
    @State private var name: String
    @State private var transcript: String
    @State private var problem: String?

    init(voice: Voice) {
        self.voice = voice
        _name = State(initialValue: voice.name)
        _transcript = State(initialValue: voice.transcript)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit “\(voice.name)”")
                .font(.title2.weight(.semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("Exact words in the clip")
                .font(.headline)
            TextEditor(text: $transcript)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))
            if let problem {
                ErrorLabel(message: problem)
            }
            HStack {
                Button("Listen to the Clip", systemImage: "play.fill") { model.playback.toggle(model.clipURL(for: voice)) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        try model.updateVoice(voice.id, name: name, transcript: transcript)
                        dismiss()
                    } catch {
                        problem = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}
