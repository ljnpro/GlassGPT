import ChatPersistenceCore
import GeneratedFilesCore
import SwiftUI

struct GeneratedPreviewPresentationState {
    var isBlockingTouches = false
    var presentedItem: FilePreviewItem?
    var isDismissPending = false
    var isShowing = false
    var dismissTask: Task<Void, Never>?
}

extension ChatView {
    var sharedGeneratedFileBinding: Binding<SharedGeneratedFileItem?> {
        Binding(
            get: {
                viewModel.sharedGeneratedFileItem
            },
            set: { newValue in
                if let newValue {
                    viewModel.sharedGeneratedFileItem = newValue
                } else {
                    viewModel.sharedGeneratedFileItem = nil
                }
            }
        )
    }

    var generatedPreviewCandidate: FilePreviewItem? {
        guard let previewItem = viewModel.filePreviewItem else { return nil }
        switch previewItem.kind {
        case .generatedImage, .generatedPDF:
            return previewItem
        }
    }

    var fileDownloadErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.fileDownloadError != nil },
            set: { if !$0 { viewModel.fileDownloadError = nil } }
        )
    }

    var shouldShowGeneratedPreviewTouchShield: Bool {
        generatedPreview.presentedItem != nil || generatedPreview.isBlockingTouches
    }

    func syncGeneratedPreviewPresentation() {
        guard let previewItem = generatedPreviewCandidate else {
            guard !generatedPreview.isDismissPending else { return }
            generatedPreview.isShowing = false
            generatedPreview.presentedItem = nil
            generatedPreview.isBlockingTouches = false
            return
        }

        generatedPreview.dismissTask?.cancel()
        generatedPreview.dismissTask = nil
        generatedPreview.presentedItem = previewItem
        generatedPreview.isDismissPending = false
        generatedPreview.isBlockingTouches = false
        if !generatedPreview.isShowing {
            generatedPreview.isShowing = true
        }
    }

    func prepareGeneratedPreviewDismissal() {
        guard generatedPreview.presentedItem != nil else { return }
        guard !generatedPreview.isDismissPending else { return }
        generatedPreview.dismissTask?.cancel()
        generatedPreview.dismissTask = nil
        generatedPreview.isDismissPending = true
        generatedPreview.isBlockingTouches = true
    }

    func beginGeneratedPreviewDismissal() {
        guard generatedPreview.presentedItem != nil else { return }
        if !generatedPreview.isDismissPending {
            prepareGeneratedPreviewDismissal()
        }

        viewModel.filePreviewItem = nil

        generatedPreview.dismissTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: generatedPreviewOverlayDismissDelay)
            } catch is CancellationError {
                // Preserve the prior swallowed-error behavior by continuing immediately on cancellation.
            } catch {
                Loggers.app.error("[ChatView] Generated preview dismissal overlay delay failed: \(error.localizedDescription)")
            }

            generatedPreview.isShowing = false

            do {
                try await Task.sleep(nanoseconds: generatedPreviewTouchCooldownDuration)
            } catch is CancellationError {
                // Preserve the prior swallowed-error behavior by continuing immediately on cancellation.
            } catch {
                Loggers.app.error("[ChatView] Generated preview touch cooldown failed: \(error.localizedDescription)")
            }

            generatedPreview.presentedItem = nil
            generatedPreview.isBlockingTouches = false
            generatedPreview.isDismissPending = false
            generatedPreview.dismissTask = nil
        }
    }

    func handleGeneratedPreviewCoverDismiss() {
        guard !generatedPreview.isShowing else { return }

        if !generatedPreview.isDismissPending {
            generatedPreview.presentedItem = nil
            generatedPreview.isBlockingTouches = false
            generatedPreview.dismissTask?.cancel()
            generatedPreview.dismissTask = nil
            viewModel.filePreviewItem = nil
        }
    }
}
