import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<Conversation>(\.updatedAt, order: .reverse)])
    private var conversations: [Conversation]

    @State private var searchText = ""
    @State private var showDeleteConfirmation = false

    var onSelectConversation: ((Conversation) -> Void)?
    var onDeleteConversation: ((Conversation) -> Void)?
    var onDeleteAllConversations: (() -> Void)?

    var body: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filteredConversations) { conversation in
                            Button {
                                onSelectConversation?(conversation)
                            } label: {
                                HistoryRow(conversation: conversation)
                            }
                            .listRowBackground(Color.clear)
                        }
                        .onDelete(perform: deleteConversations)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .searchable(text: $searchText, prompt: "Search conversations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !conversations.isEmpty {
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
                    }
                }
            }
            .alert("Delete All Conversations?", isPresented: $showDeleteConfirmation) {
                Button("Delete All", role: .destructive) {
                    deleteAllConversations()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    // MARK: - Filtered

    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Conversations Yet",
            systemImage: "clock.badge.questionmark",
            description: Text("Your chat history will appear here.")
        )
    }

    // MARK: - Delete

    private func deleteConversations(at offsets: IndexSet) {
        let toDelete = offsets.map { filteredConversations[$0] }

        for conversation in toDelete {
            onDeleteConversation?(conversation)
            modelContext.delete(conversation)
        }

        do {
            try modelContext.save()
            HapticService.shared.impact(.medium)
        } catch {
            Loggers.persistence.error("Failed to delete conversations: \(error.localizedDescription)")
        }
    }

    private func deleteAllConversations() {
        onDeleteAllConversations?()

        for conversation in conversations {
            modelContext.delete(conversation)
        }

        do {
            try modelContext.save()
            HapticService.shared.notify(.warning)
        } catch {
            Loggers.persistence.error("Failed to delete all conversations: \(error.localizedDescription)")
        }
    }
}
