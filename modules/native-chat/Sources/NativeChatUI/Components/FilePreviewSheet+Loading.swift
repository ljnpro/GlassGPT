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
            switch Self.loadGeneratedImagePreview(from: fileURL) {
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
            switch Self.loadGeneratedPDFPreview(from: fileURL) {
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
            HapticService.shared.notify(.success)
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

    static func loadGeneratedImagePreview(from fileURL: URL) -> ImagePreviewLoadResult {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return .unavailable
        }

        guard !data.isEmpty else {
            return .unavailable
        }

        guard isGeneratedImageFilename(fileURL.lastPathComponent) else {
            return .error("This file is no longer recognized as an image.")
        }

        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return .error("This generated image could not be rendered.")
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(
            imageSource,
            0,
            [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary
        ) else {
            return .error("This generated image could not be rendered.")
        }

        return .image(
            ImagePreviewPayload(
                image: UIImage(cgImage: cgImage),
                data: data
            )
        )
    }

    static func loadGeneratedPDFPreview(from fileURL: URL) -> PDFPreviewLoadResult {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return .unavailable
        }

        guard !data.isEmpty else {
            return .unavailable
        }

        guard isGeneratedPDFFilename(fileURL.lastPathComponent) else {
            return .error("This file is no longer recognized as a PDF.")
        }

        guard let document = PDFDocument(data: data) else {
            return .error("This generated PDF could not be rendered.")
        }

        return .document(document)
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

    private static func isGeneratedImageFilename(_ filename: String) -> Bool {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "webp", "gif", "bmp", "tiff", "heic"].contains(ext)
    }

    private static func isGeneratedPDFFilename(_ filename: String) -> Bool {
        URL(fileURLWithPath: filename).pathExtension.lowercased() == "pdf"
    }
}
