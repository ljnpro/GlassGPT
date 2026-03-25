import ChatDomain
import ChatPersistenceSwiftData
import ChatUIComponents
import NativeChatUI
import SwiftUI
import UIKit

/// SwiftUI surface for the dedicated Agent mode transcript, progress UI, and composer.
package struct AgentView: View {
    @Bindable var viewModel: AgentController
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @State var composerText = ""
    @State var composerHeight = Self.minimumComposerHeight
    @State var isShowingAgentSelector = false
    @State var agentSelectorDraft = AgentConversationConfiguration()
    @State var liveSummaryExpanded: Bool? = true
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
        initialLiveSummaryExpanded: Bool? = true,
        initialExpandedTraceMessageIDs: Set<UUID> = []
    ) {
        self.viewModel = viewModel
        _liveSummaryExpanded = State(initialValue: initialLiveSummaryExpanded)
        _expandedTraceMessageIDs = State(initialValue: initialExpandedTraceMessageIDs)
    }

    /// The root Agent mode layout wrapped in a navigation stack.
    package var body: some View {
        NavigationStack {
            agentContent
                .id(viewRootIdentity)
                .toolbar(.hidden, for: .navigationBar)
                .overFullScreenCover(
                    isPresented: $isShowingAgentSelector,
                    interfaceStyle: agentSelectorInterfaceStyle,
                    onDismiss: dismissAgentSelector
                ) {
                    agentSelectorPresentation
                }
                .onChange(of: viewModel.currentConversation?.id) { _, _ in
                    liveSummaryExpanded = true
                    agentSelectorDraft = viewModel.currentConfiguration
                }
                .onAppear {
                    agentSelectorDraft = viewModel.currentConfiguration
                }
        }
    }

    var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    var agentSelectorInterfaceStyle: UIUserInterfaceStyle {
        switch selectedTheme {
        case .system:
            .unspecified
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}
