import SwiftUI

/// Reusable settings section for displaying and clearing a cache (images, documents, etc.).
public struct SettingsCacheSection: View {
    /// Section header title.
    public let title: String
    /// Human-readable string showing the current cache size.
    public let usedValue: String
    /// Descriptive footer text explaining the cache purpose.
    public let footerText: String
    /// Whether a clear operation is currently in progress.
    public let isClearing: Bool
    /// Whether there is any cached content to clear.
    public let hasCachedContent: Bool
    /// Label for the clear button.
    public let clearLabel: String
    /// Async action invoked when the user taps the clear button.
    public let clearAction: @MainActor () async -> Void

    /// Creates a cache section with the given configuration.
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
