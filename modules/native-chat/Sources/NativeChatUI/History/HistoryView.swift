import ChatPresentation
import ChatUIComponents
import SwiftUI

/// Displays a searchable, deletable list of past conversations.
public struct HistoryView: View {
    @State private var viewModel: HistoryPresenter

    /// Creates a history view backed by the given presenter.
    @MainActor
    public init(store: HistoryPresenter) {
        _viewModel = State(initialValue: store)
    }

    /// The view hierarchy for the searchable history list and delete affordances.
    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.filteredConversations.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(viewModel.filteredConversations) { conversation in
                            Button {
                                viewModel.selectConversation(id: conversation.id)
                            } label: {
                                HistoryRow(conversation: conversation)
                            }
                            .accessibilityIdentifier("history.row.\(conversation.title)")
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(String(localized: "History"))
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search")
            )
        }
        .onAppear {
            viewModel.refresh()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: viewModel.isSignedIn ? "clock.badge.questionmark" : "person.crop.circle.badge.exclamationmark")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(viewModel.isSignedIn ? String(localized: "No Conversations Yet") : String(localized: "Sign In to Sync History"))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                viewModel.isSignedIn
                    ? String(localized: "Your chat history will appear here.")
                    : String(localized: "Sign in with Apple in Settings to sync conversations, agent runs, and results across devices.")
            )
            .font(.body)
            .foregroundStyle(.primary.opacity(0.78))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            if !viewModel.isSignedIn {
                SettingsCallToActionButton(
                    title: String(localized: "Open Settings"),
                    accessibilityIdentifier: "glassgpt.history.openSettings"
                ) {
                    viewModel.openSettings()
                }
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("history.emptyState")
    }
}
