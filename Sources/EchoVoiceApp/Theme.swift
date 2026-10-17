import AppKit
import EchoVoiceCore
import SwiftUI

private struct WindowWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = CGFloat(PageLayout.standardWindowWidth)
}

extension EnvironmentValues {
    /// The window's current width, set once by `RootView`, so pages can grow with the window.
    var windowWidth: CGFloat {
        get { self[WindowWidthKey.self] }
        set { self[WindowWidthKey.self] = newValue }
    }
}

/// Pearl Editorial: warm paper, deep teal, and a comfortable reading measure.
enum Theme {
    static let canvas = Color(red: 0.949, green: 0.937, blue: 0.906)
    static let paper = Color(red: 0.992, green: 0.988, blue: 0.969)
    static let soft = Color(red: 0.910, green: 0.906, blue: 0.867)
    static let ink = Color(red: 0.14, green: 0.18, blue: 0.19)
    static let muted = Color(red: 0.36, green: 0.40, blue: 0.39)
    static let rule = Color(red: 0.81, green: 0.81, blue: 0.76)
    static let accent = Color(red: 0.20, green: 0.35, blue: 0.35)
    static let accentLight = Color(red: 0.82, green: 0.88, blue: 0.85)
    static let success = Color(red: 0.20, green: 0.40, blue: 0.31)

    static func editorial(_ size: CGFloat) -> Font {
        .custom("Baskerville", size: size)
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.editorial(38))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Page<Content: View>: View {
    let title: String
    let subtitle: String
    var showsPrivacyFooter = true
    @ViewBuilder let content: () -> Content
    @Environment(\.windowWidth) private var windowWidth

    var body: some View {
        // The page is at least as tall as the window, so a flexible part (the script editor) can
        // grow into the spare room. When there isn't any, the page scrolls as before.
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    PageHeader(title: title, subtitle: subtitle)
                    content()
                    if showsPrivacyFooter {
                        PrivacyFooter()
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 34)
                .frame(maxWidth: CGFloat(PageLayout.contentWidth(forWindow: Double(windowWidth))),
                       minHeight: proxy.size.height, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(Theme.canvas)
    }
}

struct PearlPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(22)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.rule.opacity(0.65)))
    }
}

struct PearlGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            configuration.label
                .font(.system(size: 11, weight: .medium))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(Theme.muted)
            configuration.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PearlPanel())
    }
}

struct PearlPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .foregroundStyle(Theme.paper)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 5))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}

struct PearlSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(configuration.role == .destructive ? Color.red : Theme.accent)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.rule))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
    }
}

struct VoiceInitial: View {
    let name: String
    var size: CGFloat = 48

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(Theme.editorial(size * 0.48))
            .foregroundStyle(Theme.accent)
            .frame(width: size, height: size)
            .background(Theme.accentLight.opacity(0.5), in: Circle())
            .accessibilityHidden(true)
    }
}

struct PrivacyFooter: View {
    var body: some View {
        Label("Processed on your Mac", systemImage: "checkmark.shield")
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)
    }
}

struct Caption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ErrorLabel: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct WarningLabel: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.callout)
            .foregroundStyle(Color(red: 0.55, green: 0.30, blue: 0.08))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct MessageBar: View {
    let text: String
    let isError: Bool
    var actionTitle: String? = nil
    var action: () -> Void = {}
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? Color.red : Theme.success)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let actionTitle {
                Button(actionTitle, action: action)
            }
            Button("Dismiss", action: dismiss)
        }
        .padding(16)
        .foregroundStyle(Theme.ink)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isError ? Color.red.opacity(0.4) : Theme.rule))
        .shadow(color: Theme.ink.opacity(0.10), radius: 12, y: 5)
        .accessibilityElement(children: .contain)
    }
}

enum DateText {
    static func medium(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
