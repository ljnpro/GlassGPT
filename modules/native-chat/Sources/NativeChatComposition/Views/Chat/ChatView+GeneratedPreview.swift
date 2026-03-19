import ChatPersistenceCore
import GeneratedFilesCore
import SwiftUI

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
        presentedGeneratedPreviewItem != nil || isBlockingGeneratedPreviewTouches
    }

    func syncGeneratedPreviewPresentation() {
        guard let previewItem = generatedPreviewCandidate else {
            guard !isGeneratedPreviewDismissPending else { return }
            isShowingGeneratedPreview = false
            presentedGeneratedPreviewItem = nil
            isBlockingGeneratedPreviewTouches = false
            return
        }

        generatedPreviewDismissTask?.cancel()
        generatedPreviewDismissTask = nil
        presentedGeneratedPreviewItem = previewItem
        isGeneratedPreviewDismissPending = false
        isBlockingGeneratedPreviewTouches = false
        if !isShowingGeneratedPreview {
            isShowingGeneratedPreview = true
        }
    }

    func prepareGeneratedPreviewDismissal() {
        guard presentedGeneratedPreviewItem != nil else { return }
        guard !isGeneratedPreviewDismissPending else { return }
        generatedPreviewDismissTask?.cancel()
        generatedPreviewDismissTask = nil
        isGeneratedPreviewDismissPending = true
        isBlockingGeneratedPreviewTouches = true
    }

    func beginGeneratedPreviewDismissal() {
        guard presentedGeneratedPreviewItem != nil else { return }
        if !isGeneratedPreviewDismissPending {
            prepareGeneratedPreviewDismissal()
        }

        viewModel.filePreviewItem = nil

        generatedPreviewDismissTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: generatedPreviewOverlayDismissDelay)
            } catch is CancellationError {
                // Preserve the prior swallowed-error behavior by continuing immediately on cancellation.
            } catch {
                Loggers.app.error("[ChatView] Generated preview dismissal overlay delay failed: \(error.localizedDescription)")
            }

            isShowingGeneratedPreview = false

            do {
                try await Task.sleep(nanoseconds: generatedPreviewTouchCooldownDuration)
            } catch is CancellationError {
                // Preserve the prior swallowed-error behavior by continuing immediately on cancellation.
            } catch {
                Loggers.app.error("[ChatView] Generated preview touch cooldown failed: \(error.localizedDescription)")
            }

            presentedGeneratedPreviewItem = nil
            isBlockingGeneratedPreviewTouches = false
            isGeneratedPreviewDismissPending = false
            generatedPreviewDismissTask = nil
        }
    }

    func handleGeneratedPreviewCoverDismiss() {
        guard !isShowingGeneratedPreview else { return }

        if !isGeneratedPreviewDismissPending {
            presentedGeneratedPreviewItem = nil
            isBlockingGeneratedPreviewTouches = false
            generatedPreviewDismissTask?.cancel()
            generatedPreviewDismissTask = nil
            viewModel.filePreviewItem = nil
        }
    }
}
