import SwiftUI

public struct SettingsCacheSection: View {
    public let title: String
    public let usedValue: String
    public let footerText: String
    public let isClearing: Bool
    public let hasCachedContent: Bool
    public let clearLabel: String
    public let clearAction: @MainActor () async -> Void

    public init(
        title: String,
        usedValue: String,
        footerText: String,
        isClearing: Bool,
        hasCachedContent: Bool,
        clearLabel: String,
        clearAction: @escaping @MainActor () async -> Void
    ) {
        self.title = title
        self.usedValue = usedValue
        self.footerText = footerText
        self.isClearing = isClearing
        self.hasCachedContent = hasCachedContent
        self.clearLabel = clearLabel
        self.clearAction = clearAction
    }

    public var body: some View {
        Section {
            LabeledContent("Used", value: usedValue)

            Button(role: .destructive) {
                Task { @MainActor in
                    await clearAction()
                }
            } label: {
                HStack {
                    if isClearing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(clearLabel)
                }
            }
            .disabled(isClearing || !hasCachedContent)
        } header: {
            Text(title)
        } footer: {
            Text(footerText)
        }
    }
}
