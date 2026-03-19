import ChatPresentation
import ChatUIComponents
import SwiftUI

/// Displays a searchable, deletable list of past conversations.
public struct HistoryView: View {
    @State private var showDeleteConfirmation = false
    @State private var viewModel: HistoryPresenter

    @MainActor
    /// Creates a history view backed by the given presenter.
    public init(store: HistoryPresenter) {
        _viewModel = State(initialValue: store)
    }

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
            .navigationTitle("History")
            .searchable(text: $viewModel.searchText, prompt: "Search conversations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.conversations.isEmpty {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete All", systemImage: "trash")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .singleFrameGlassCapsuleControl(
                                    tintOpacity: 0.015,
                                    borderWidth: 0.78,
                                    darkBorderOpacity: 0.14,
                                    lightBorderOpacity: 0.08
                                )
                        }
                        .buttonStyle(GlassPressButtonStyle())
                        .accessibilityIdentifier("history.deleteAll")
                    }
                }
            }
            .alert("Delete All Conversations?", isPresented: $showDeleteConfirmation) {
                Button("Delete All", role: .destructive) {
                    viewModel.deleteAllConversations()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
        .onAppear {
            viewModel.refresh()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Conversations Yet",
            systemImage: "clock.badge.questionmark",
            description: Text("Your chat history will appear here.")
        )
    }

    private func deleteConversations(at offsets: IndexSet) {
        let toDelete = offsets.map { viewModel.filteredConversations[$0].id }
        for conversationID in toDelete {
            viewModel.deleteConversation(id: conversationID)
        }
    }
}
