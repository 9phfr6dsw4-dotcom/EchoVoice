import AppKit
import SwiftUI

/// The same look as EchoFlow, EchoLedger, Lumen and Quick Drop Zone.
enum Theme {
    static let accent = Color(red: 0.17, green: 0.49, blue: 0.94)
    static let accentLight = Color(red: 0.55, green: 0.88, blue: 1.0)
    static let success = Color(red: 0.16, green: 0.62, blue: 0.40)
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.weight(.semibold))
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A scrolling page: large title, subtitle, content, privacy footer.
struct Page<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: title, subtitle: subtitle)
                content()
                PrivacyFooter()
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct PrivacyFooter: View {
    var body: some View {
        Label("Your voices, scripts and recordings stay on this Mac. Nothing is uploaded.", systemImage: "lock.shield")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

struct Caption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
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
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct MessageBar: View {
    let text: String
    let isError: Bool
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? Color.red : Theme.success)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Dismiss", action: dismiss)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .background(isError ? Color.red.opacity(0.18) : Theme.success.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}

enum DateText {
    static func medium(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
