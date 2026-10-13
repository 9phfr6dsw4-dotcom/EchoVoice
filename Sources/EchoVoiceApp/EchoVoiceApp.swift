import AppKit
import EchoVoiceCore
import SwiftUI

@main
@MainActor
struct EchoVoiceApp: App {
    @State private var model = AppModel()

    init() {
        if CommandLine.arguments.contains("--mlx-self-test") {
            MLXSelfTest.runAndExit()
        }
    }

    var body: some Scene {
        WindowGroup("EchoVoice") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1080, height: 760)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.section = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("Recording") {
                Button("Make Recording") {
                    model.section = .write
                    model.generate()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.isGenerating || model.isDownloading)
                Button("Stop") { model.stop() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.isGenerating)
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
        NavigationSplitView {
            List(selection: sectionSelection) {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            // Messages float over the page, so showing one never shifts the layout.
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        if let message = model.errorMessage {
                            MessageBar(text: message, isError: true) { model.errorMessage = nil }
                        }
                        if let message = model.statusMessage {
                            MessageBar(text: message, isError: false) { model.statusMessage = nil }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: 720)
                }
        }
        .navigationTitle(model.section.title)
        .task(id: model.statusMessage) {
            guard model.statusMessage != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            model.statusMessage = nil
        }
    }

    private var sectionSelection: Binding<AppSection?> {
        Binding(get: { model.section }, set: { value in
            if let value { model.section = value }
        })
    }

    @ViewBuilder
    private var detail: some View {
        switch model.section {
        case .write: WriteView()
        case .voices: VoicesView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}
