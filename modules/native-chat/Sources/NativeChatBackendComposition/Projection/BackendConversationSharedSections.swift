import ChatDomain
import ChatUIComponents
import NativeChatBackendCore
import NativeChatUI
import SwiftUI

struct BackendConversationEmptyStateCard: View {
    let systemImageName: String
    let symbolSecondaryOpacity: Double
    let showsSymbolEffect: Bool
    let title: LocalizedStringKey
    let description: String
    let isSignedIn: Bool
    let descriptionSignedOutWeight: Font.Weight
    let descriptionMaxWidth: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let accessibilityIdentifier: String
    let settingsAccessibilityIdentifier: String
    let openSettings: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.16), Color.cyan.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 108, height: 108)

                symbolView
            }

            Text(title)
                .font(.title2.weight(.semibold))

            Text(description)
                .font(.callout.weight(isSignedIn ? .regular : descriptionSignedOutWeight))
                .foregroundStyle(isSignedIn ? Color.primary.opacity(0.78) : .primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: descriptionMaxWidth)

            if !isSignedIn {
                SettingsCallToActionButton(
                    title: String(localized: "Open Account & Sync"),
                    accessibilityIdentifier: settingsAccessibilityIdentifier
                ) {
                    openSettings()
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var symbolView: some View {
        let base = Image(systemName: systemImageName)
            .font(.system(size: 38, weight: .semibold))
            .foregroundStyle(.blue, .primary.opacity(symbolSecondaryOpacity))
            .accessibilityHidden(true)

        if showsSymbolEffect {
            base.symbolEffect(.breathe)
        } else {
            base
        }
    }
}

protocol BackendConversationMessageListDisplaying: BackendConversationDisplayState {
    var errorMessage: String? { get }
}

extension BackendChatController: BackendConversationMessageListDisplaying {}
extension BackendAgentController: BackendConversationMessageListDisplaying {}

struct BackendConversationMessageListCore<
    ViewModel: BackendConversationMessageListDisplaying,
    MessagePrefix: View,
    MessageSuffix: View,
    DetachedTail: View
>: View {
    let viewModel: ViewModel
    let assistantBubbleMaxWidth: CGFloat
    @Binding var streamingThinkingExpanded: Bool?
    let messagePrefix: (BackendMessageSurface) -> MessagePrefix
    let messageSuffix: (BackendMessageSurface) -> MessageSuffix
    let detachedTail: () -> DetachedTail

    var body: some View {
        VStack(spacing: 16) {
            ForEach(viewModel.messages) { message in
                VStack(alignment: .leading, spacing: 10) {
                    messagePrefix(message)

                    MessageBubble(
                        message: message,
                        liveContent: viewModel.liveDraftMessageID == message.id ? viewModel.currentStreamingText : nil,
                        liveThinking: viewModel.liveDraftMessageID == message.id ? viewModel.currentThinkingText : nil,
                        activeToolCalls: viewModel.liveDraftMessageID == message.id ? viewModel.activeToolCalls : [],
                        liveCitations: viewModel.liveDraftMessageID == message.id ? viewModel.liveCitations : [],
                        liveFilePathAnnotations: viewModel.liveDraftMessageID == message.id ? viewModel.liveFilePathAnnotations : [],
                        isLiveThinking: viewModel.liveDraftMessageID == message.id && viewModel.isThinking,
                        liveThinkingPresentationState: viewModel.liveDraftMessageID == message.id
                            ? viewModel.thinkingPresentationState
                            : nil
                    )
                    .equatable()
                    .id(message.id)

                    messageSuffix(message)
                }
            }

            if viewModel.shouldShowDetachedStreamingBubble {
                DetachedStreamingBubbleView(
                    activeToolCalls: viewModel.activeToolCalls,
                    currentThinkingText: viewModel.currentThinkingText,
                    currentStreamingText: viewModel.currentStreamingText,
                    isThinking: viewModel.isThinking,
                    isStreaming: viewModel.isConversationRunActive,
                    thinkingPresentationState: viewModel.thinkingPresentationState,
                    liveCitations: viewModel.liveCitations,
                    liveFilePathAnnotations: viewModel.liveFilePathAnnotations,
                    streamingThinkingExpanded: $streamingThinkingExpanded,
                    assistantBubbleMaxWidth: assistantBubbleMaxWidth
                )
                .equatable()
            }

            detachedTail()

            if let errorMessage = viewModel.errorMessage {
                BackendConversationErrorBanner(message: errorMessage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
