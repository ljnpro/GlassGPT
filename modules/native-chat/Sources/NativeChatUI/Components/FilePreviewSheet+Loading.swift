import Foundation
import ImageIO
import PDFKit
import Photos
import ChatUIComponents
import SwiftUI

extension FilePreviewSheet {
    @MainActor
    func loadPreview() async {
        switch previewItem.kind {
        case .generatedImage:
            await loadImagePreview()
        case .generatedPDF:
            await loadPDFPreview()
        }
    }

    @MainActor
    func loadImagePreview() async {
        imagePreviewState = .loading

        for attempt in 0..<4 {
            switch FilePreviewLoadingModel.loadGeneratedImagePreview(from: fileURL) {
            case .image(let payload):
                imagePreviewState = .image(payload)
                return
            case .error(let message):
                imagePreviewState = .error(message)
                return
            case .unavailable:
                if attempt < 3 {
                    do {
                        try await Task.sleep(nanoseconds: 150_000_000)
                    } catch {
                        return
                    }
                } else {
                    imagePreviewState = .error("This generated image could not be loaded.")
                }
            }
        }
    }

    @MainActor
    func loadPDFPreview() async {
        pdfPreviewState = .loading

        for attempt in 0..<4 {
            switch FilePreviewLoadingModel.loadGeneratedPDFPreview(from: fileURL) {
            case .document(let document):
                pdfPreviewState = .document(document)
                return
            case .error(let message):
                pdfPreviewState = .error(message)
                return
            case .unavailable:
                if attempt < 3 {
                    do {
                        try await Task.sleep(nanoseconds: 150_000_000)
                    } catch {
                        return
                    }
                } else {
                    pdfPreviewState = .error("This generated PDF could not be loaded.")
                }
            }
        }
    }

    @MainActor
    func saveImageToPhotos() async {
        guard let imagePreviewPayload, canSaveToPhotos, saveState != .saving else { return }

        saveState = .saving

        let authorization = await requestPhotoAccess()
        guard authorization == .authorized || authorization == .limited else {
            saveState = .idle
            saveError = "Photo Library access is required to save images."
            return
        }

        do {
            try await PhotoLibraryImageSaver.saveImageData(
                imagePreviewPayload.data,
                originalFilename: previewItem.viewerFilename
            )
            saveState = .idle
            hapticService.notify(.success, isEnabled: hapticsEnabled)
            UIAccessibility.post(notification: .announcement, argument: "Saved to Photos")
            showSaveSuccessFeedback()
        } catch {
            saveState = .idle
            saveError = error.localizedDescription
        }
    }

    func requestPhotoAccess() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    func presentShareSheet() {
        isShowingShareSheet = true
    }

    func showSaveSuccessFeedback() {
        let token = UUID()
        saveSuccessHUDToken = token

        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            showSaveSuccessHUD = true
        }

        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_600_000_000)
            } catch {
                return
            }

            guard saveSuccessHUDToken == token else { return }

            withAnimation(.easeInOut(duration: 0.2)) {
                showSaveSuccessHUD = false
            }
        }
    }
}
