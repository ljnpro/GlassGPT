import ChatUIComponents
import SwiftUI

public struct NativeChatRootTabsView: View {
    private let title: String

    public init(title: String = "Native Chat") {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .padding()
            .modifier(StaticRoundedGlassShellModifier(cornerRadius: 18))
    }
}
