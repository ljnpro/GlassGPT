import ChatDomain
import ChatPersistenceCore
import NativeChatBackendCore
import NativeChatUI
import PhotosUI
import SwiftUI
import UIKit

/// Shared non-view helpers for backend-owned conversation roots.
package enum BackendConversationViewSupport {
    private static let selectedPhotoCompressionQuality: CGFloat = 0.85

    package static func selectedTheme(rawValue: String) -> AppTheme {
        AppTheme(rawValue: rawValue) ?? .system
    }

    package static func resolvedInterfaceStyle(
        selectedTheme: AppTheme,
        systemColorScheme: ColorScheme
    ) -> UIUserInterfaceStyle {
        if let explicit = selectedTheme.colorScheme {
            return explicit == .dark ? .dark : .light
        }
        return systemColorScheme == .dark ? .dark : .light
    }

    @MainActor
    package static func assistantBubbleMaxWidth() -> CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 680 : 520
    }

    @MainActor
    package static func dismissKeyboard() {
        KeyboardDismisser.dismiss()
    }

    package static func showsEmptyState(
        messages: [BackendMessageSurface],
        isRunActive: Bool
    ) -> Bool {
        messages.isEmpty && !isRunActive
    }

    package static func hashSharedLiveBottomAnchor(
        into hasher: inout Hasher,
        conversationID: UUID?,
        liveDraftMessageID: UUID?,
        isThinking: Bool,
        isRunActive: Bool,
        activeToolCalls: [ToolCallInfo],
        liveCitationsCount: Int,
        liveFilePathAnnotationsCount: Int
    ) {
        hasher.combine(conversationID)
        hasher.combine(liveDraftMessageID)
        hasher.combine(isThinking)
        hasher.combine(isRunActive)
        hasher.combine(activeToolCalls.count)
        hasher.combine(liveCitationsCount)
        hasher.combine(liveFilePathAnnotationsCount)
        for toolCall in activeToolCalls {
            hasher.combine(toolCall.id)
            hasher.combine(toolCall.status.rawValue)
        }
    }

    package static func loadSelectedPhoto(
        _ item: PhotosPickerItem?,
        failurePrefix: String,
        assign: @MainActor @escaping (Data) -> Void
    ) async {
        do {
            guard
                let rawData = try await item?.loadTransferable(type: Data.self),
                let image = UIImage(data: rawData),
                let jpegData = image.jpegData(compressionQuality: selectedPhotoCompressionQuality)
            else {
                return
            }
            await assign(jpegData)
        } catch {
            Loggers.files.error("\(failurePrefix): \(error.localizedDescription)")
        }
    }
}
