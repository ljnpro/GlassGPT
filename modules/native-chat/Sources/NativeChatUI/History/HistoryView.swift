import ChatPresentation
import ChatUIComponents
import SwiftUI

/// Displays a searchable, deletable list of past conversations.
public struct HistoryView: View {
    @State private var showDeleteConfirmation = false
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
                        .onDelete(perform: deleteConversations)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(String(localized: "History"))
            .searchable(text: $viewModel.searchText, prompt: String(localized: "Search conversations"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.conversations.isEmpty {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label(String(localized: "Delete All"), systemImage: "trash")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .singleFrameGlassCapsuleControl(
                                    tintOpacity: GlassStyleMetrics.CapsuleControl.tintOpacity,
                                    borderWidth: GlassStyleMetrics.CapsuleControl.borderWidth,
                                    darkBorderOpacity: GlassStyleMetrics.CapsuleControl.darkBorderOpacity,
                                    lightBorderOpacity: GlassStyleMetrics.CapsuleControl.lightBorderOpacity
                                )
                        }
                        .buttonStyle(GlassPressButtonStyle())
                        .accessibilityLabel(String(localized: "Delete all conversations"))
                        .accessibilityIdentifier("history.deleteAll")
                    }
                }
            }
            .alert(String(localized: "Delete All Conversations?"), isPresented: $showDeleteConfirmation) {
                Button(String(localized: "Delete All"), role: .destructive) {
                    viewModel.deleteAllConversations()
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "This action cannot be undone."))
            }
        }
        .onAppear {
            viewModel.refresh()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            String(localized: "No Conversations Yet"),
            systemImage: "clock.badge.questionmark",
            description: Text(String(localized: "Your chat history will appear here."))
        )
        .accessibilityIdentifier("history.emptyState")
    }

    private func deleteConversations(at offsets: IndexSet) {
        let toDelete = offsets.map { viewModel.filteredConversations[$0].id }
        for conversationID in toDelete {
            viewModel.deleteConversation(id: conversationID)
        }
    }
}
