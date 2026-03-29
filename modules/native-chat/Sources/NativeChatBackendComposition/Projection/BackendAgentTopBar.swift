import ChatUIComponents
import NativeChatBackendCore
import NativeChatUI
import SwiftUI

struct BackendAgentTopBar: View {
    @Bindable var viewModel: BackendAgentController
    let onOpenSelector: () -> Void
    let onStartNewConversation: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ConversationSelectorCapsuleButton(
                title: viewModel.compactConfigurationSummary,
                leadingSystemIcon: "person.3.sequence.fill",
                trailingSystemIcons: viewModel.selectorStatusIcons,
                accessibilityLabel: "Agent Council",
                accessibilityValue: viewModel.configurationSummary,
                accessibilityHint: "Open Agent settings",
                accessibilityIdentifier: "backendAgent.selector",
                onTap: onOpenSelector
            )

            ConversationNewButton(
                accessibilityLabel: "Start new Agent conversation",
                accessibilityIdentifier: "backendAgent.newConversation",
                onTap: onStartNewConversation
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}
