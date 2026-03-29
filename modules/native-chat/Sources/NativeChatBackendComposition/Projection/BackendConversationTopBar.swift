import NativeChatBackendCore
import NativeChatUI
import Observation
import SwiftUI

@MainActor
protocol BackendConversationTopBarDisplaying: AnyObject, Observable {
    var topBarTitle: String { get }
    var topBarLeadingSystemIcon: String? { get }
    var selectorStatusIcons: [String] { get }
    var selectorAccessibilityLabel: String { get }
    var selectorAccessibilityValue: String { get }
    var selectorAccessibilityHint: String { get }
    var selectorAccessibilityIdentifier: String { get }
    var newConversationAccessibilityLabel: String { get }
    var newConversationAccessibilityIdentifier: String { get }
}

@MainActor
extension BackendChatController: BackendConversationTopBarDisplaying {
    var topBarTitle: String {
        configurationSummary
    }

    var topBarLeadingSystemIcon: String? {
        nil
    }

    var selectorAccessibilityLabel: String {
        "Model"
    }

    var selectorAccessibilityValue: String {
        configurationSummary
    }

    var selectorAccessibilityHint: String {
        "Open model settings"
    }

    var selectorAccessibilityIdentifier: String {
        "backendChat.selector"
    }

    var newConversationAccessibilityLabel: String {
        "Start new chat"
    }

    var newConversationAccessibilityIdentifier: String {
        "backendChat.newConversation"
    }
}

@MainActor
extension BackendAgentController: BackendConversationTopBarDisplaying {
    var topBarTitle: String {
        compactConfigurationSummary
    }

    var topBarLeadingSystemIcon: String? {
        "person.3.sequence.fill"
    }

    var selectorAccessibilityLabel: String {
        "Agent Council"
    }

    var selectorAccessibilityValue: String {
        configurationSummary
    }

    var selectorAccessibilityHint: String {
        "Open Agent settings"
    }

    var selectorAccessibilityIdentifier: String {
        "backendAgent.selector"
    }

    var newConversationAccessibilityLabel: String {
        "Start new Agent conversation"
    }

    var newConversationAccessibilityIdentifier: String {
        "backendAgent.newConversation"
    }
}

struct BackendConversationTopBarSection<ViewModel: BackendConversationTopBarDisplaying>: View {
    @Bindable var viewModel: ViewModel
    let onOpenSelector: () -> Void
    let onStartNewConversation: () -> Void

    var body: some View {
        BackendConversationTopBar(
            title: viewModel.topBarTitle,
            leadingSystemIcon: viewModel.topBarLeadingSystemIcon,
            trailingSystemIcons: viewModel.selectorStatusIcons,
            selectorAccessibilityLabel: viewModel.selectorAccessibilityLabel,
            selectorAccessibilityValue: viewModel.selectorAccessibilityValue,
            selectorAccessibilityHint: viewModel.selectorAccessibilityHint,
            selectorAccessibilityIdentifier: viewModel.selectorAccessibilityIdentifier,
            newConversationAccessibilityLabel: viewModel.newConversationAccessibilityLabel,
            newConversationAccessibilityIdentifier: viewModel.newConversationAccessibilityIdentifier,
            onOpenSelector: onOpenSelector,
            onStartNewConversation: onStartNewConversation
        )
    }
}

struct BackendConversationTopBar: View {
    let title: String
    let leadingSystemIcon: String?
    let trailingSystemIcons: [String]
    let selectorAccessibilityLabel: String
    let selectorAccessibilityValue: String
    let selectorAccessibilityHint: String
    let selectorAccessibilityIdentifier: String
    let newConversationAccessibilityLabel: String
    let newConversationAccessibilityIdentifier: String
    let onOpenSelector: () -> Void
    let onStartNewConversation: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ConversationSelectorCapsuleButton(
                title: title,
                leadingSystemIcon: leadingSystemIcon,
                trailingSystemIcons: trailingSystemIcons,
                accessibilityLabel: selectorAccessibilityLabel,
                accessibilityValue: selectorAccessibilityValue,
                accessibilityHint: selectorAccessibilityHint,
                accessibilityIdentifier: selectorAccessibilityIdentifier,
                onTap: onOpenSelector
            )

            ConversationNewButton(
                accessibilityLabel: newConversationAccessibilityLabel,
                accessibilityIdentifier: newConversationAccessibilityIdentifier,
                onTap: onStartNewConversation
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}
