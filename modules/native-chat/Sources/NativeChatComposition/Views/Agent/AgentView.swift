import ChatDomain
import ChatPersistenceSwiftData
import ChatUIComponents
import SwiftUI
import UIKit

/// SwiftUI surface for the dedicated Agent mode transcript, progress UI, and composer.
package struct AgentView: View {
    @Bindable var viewModel: AgentController
    @State var composerText = ""
    @State var composerHeight = Self.minimumComposerHeight
    @State var scrollRequestID = UUID()
    @State var expandedTraceMessageIDs: Set<UUID> = []

    static let emptyConversationRootID = "agent.empty.root"
    static let horizontalTextInset: CGFloat = 12
    static let verticalTextInset: CGFloat = 8
    static let composerFont = UIFont.preferredFont(forTextStyle: .body)
    static let minimumComposerHeight = ceil(composerFont.lineHeight + (verticalTextInset * 2))
    static let maximumComposerHeight = ceil((composerFont.lineHeight * 6) + (verticalTextInset * 2))

    /// Creates an Agent view backed by the given controller and optional expanded process-card state.
    package init(
        viewModel: AgentController,
        initialExpandedTraceMessageIDs: Set<UUID> = []
    ) {
        self.viewModel = viewModel
        _expandedTraceMessageIDs = State(initialValue: initialExpandedTraceMessageIDs)
    }

    /// The root Agent mode layout wrapped in a navigation stack.
    package var body: some View {
        NavigationStack {
            agentContent
                .id(viewRootIdentity)
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}
