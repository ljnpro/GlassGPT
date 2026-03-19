import ChatUIComponents
import SwiftUI

/// Placeholder root tab view displaying a title inside a glass shell.
public struct NativeChatRootTabsView: View {
    private let title: String

    /// Creates a root tabs view with the given title string.
    public init(title: String = String(localized: "Native Chat")) {
        self.title = title
    }

    /// The placeholder glass-shell content shown for the root tabs surface.
    public var body: some View {
        Text(title)
            .padding()
            .modifier(StaticRoundedGlassShellModifier(cornerRadius: 18))
    }
}
