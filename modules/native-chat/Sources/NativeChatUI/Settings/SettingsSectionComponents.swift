import ChatUIComponents
import SwiftUI

struct SettingsSectionHeaderText: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(textColor)
            .textCase(nil)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textColor: Color {
        colorScheme == .dark ? .white : .black
    }
}

struct SettingsSectionFooterText: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(textColor)
            .textCase(nil)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textColor: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color.black.opacity(0.9)
    }
}

struct SettingsToggleLabel: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.body.weight(.medium))
            .foregroundStyle(textColor)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(labelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var labelBackground: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.08)
        }

        return Color.white.opacity(0.98)
    }
}

struct SettingsGlassSection<Content: View>: View {
    let title: String
    let footerText: String?
    let content: Content

    init(
        title: String,
        footerText: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footerText = footerText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeaderText(title: title)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .staticRoundedGlassShell(cornerRadius: 28)

            if let footerText, !footerText.isEmpty {
                SettingsSectionFooterText(text: footerText)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsSectionDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.primary.opacity(0.08))
    }
}

struct SettingsBooleanRow: View {
    let title: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            SettingsToggleLabel(text: title)

            Spacer(minLength: 12)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.accentColor)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(isOn ? String(localized: "On") : String(localized: "Off"))
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var rowBackground: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.12)
        }

        return Color.white.opacity(0.92)
    }
}
