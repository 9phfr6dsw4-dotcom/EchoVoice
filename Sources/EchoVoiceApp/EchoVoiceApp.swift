import AppKit
import EchoVoiceCore
import SwiftUI

@main
@MainActor
struct EchoVoiceApp: App {
    @State private var model: AppModel

    init() {
        if CommandLine.arguments.contains("--ci-design-review") {
            CIReviewCapture.runAndExit()
        }
        if CommandLine.arguments.contains("--mlx-self-test") {
            MLXSelfTest.runAndExit()
        }
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup("EchoVoice") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 840)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.section = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("Audio") {
                Button("Generate Audio") {
                    model.section = .generate
                    model.generate()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.isGenerating || model.isDownloading)
                Button("Stop") { model.stop() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.isGenerating)
                Divider()
                Button("New Script") {
                    model.section = .generate
                    model.newScript()
                }
                .disabled(model.isGenerating || (model.script.isEmpty && model.direction.isEmpty))
            }
            CommandMenu("Go") {
                ForEach(AppSection.allCases) { section in
                    Button(section.title) { model.section = section }
                        .keyboardShortcut(KeyEquivalent(section.shortcut), modifiers: .command)
                }
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                navigationBar(windowWidth: proxy.size.width)
                Rectangle()
                    .fill(Theme.rule)
                    .frame(height: 1)
                // Messages float over the page, so Undo and errors never shift the editor.
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        VStack(spacing: 8) {
                            if let message = model.errorMessage {
                                MessageBar(text: message, isError: true, dismiss: { model.errorMessage = nil })
                            }
                            if let message = model.statusMessage {
                                MessageBar(
                                    text: message,
                                    isError: false,
                                    actionTitle: model.canUndoNewScript ? "Undo" : nil,
                                    action: { model.undoNewScript() },
                                    dismiss: { model.statusMessage = nil }
                                )
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: 720)
                    }
            }
            .environment(\.windowWidth, proxy.size.width)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .buttonStyle(PearlSecondaryButtonStyle())
        .groupBoxStyle(PearlGroupBoxStyle())
        .preferredColorScheme(.light)
        .navigationTitle("EchoVoice")
        .task(id: model.statusMessage) {
            guard model.statusMessage != nil else { return }
            // Messages with an Undo button stay up longer.
            try? await Task.sleep(for: .seconds(model.canUndoNewScript ? 10 : 5))
            model.statusMessage = nil
        }
    }

    private func navigationBar(windowWidth: CGFloat) -> some View {
        HStack(spacing: 30) {
            HStack(spacing: 10) {
                Text("E")
                    .font(Theme.editorial(32).italic())
                    .foregroundStyle(Theme.accent)
                    .frame(width: 42, height: 42)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                Text("EchoVoice")
                    .font(Theme.editorial(25))
            }
            HStack(spacing: 4) {
                ForEach(AppSection.allCases) { section in
                    Button {
                        model.section = section
                    } label: {
                        Label(section.title, systemImage: section.symbol)
                            .font(.system(size: 12, weight: model.section == section ? .semibold : .regular))
                            .foregroundStyle(model.section == section ? Theme.accent : Theme.muted)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 25)
                            .overlay(alignment: .bottom) {
                                if model.section == section {
                                    Rectangle().fill(Theme.accent).frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.section == section ? .isSelected : [])
                    .help("\(section.title) (⌘\(String(section.shortcut)))")
                }
            }
            Spacer(minLength: 0)
            Label("On your Mac", systemImage: "lock.shield")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 30)
        // The same width as the page's content column, so the logo and the headline stay lined up
        // at every window size.
        .frame(maxWidth: CGFloat(PageLayout.contentWidth(forWindow: Double(windowWidth))))
        .frame(maxWidth: .infinity)
        .background(Theme.canvas)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.section {
        case .generate: GenerateView()
        case .voices: VoicesView()
        case .recordings: RecordingsView()
        case .settings: SettingsView()
        }
    }
}

