import ImageIO
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FilePreviewSheet: View {
    let fileURL: URL

    @State private var saveState: SaveState = .idle
    @State private var saveError: String?
    @State private var imagePreview: ImagePreviewPayload?
    @State private var isLoadingPreview = true
    @State private var isShowingShareSheet = false

    private struct ImagePreviewPayload {
        let image: UIImage
        let data: Data
        let contentType: UTType
    }

    private enum ImagePreviewLoadResult {
        case image(ImagePreviewPayload)
        case notImage
        case unavailable
    }

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
    }

    private var canSaveToPhotos: Bool {
        imagePreview != nil
    }

    private var fileDisplayName: String {
        let trimmed = fileURL.deletingPathExtension().lastPathComponent
        return trimmed.isEmpty ? fileURL.lastPathComponent : trimmed
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let imagePreview {
                imagePreviewView(imagePreview.image)
            } else if isLoadingPreview {
                loadingState
            } else {
                FilePreviewController(fileURL: fileURL)
                    .ignoresSafeArea()
            }

            if imagePreview != nil {
                headerActions
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
            }
        }
        .task(id: fileURL) {
            await loadImagePreview()
        }
        .sheet(isPresented: $isShowingShareSheet) {
            ActivityViewController(activityItems: shareItems)
        }
        .alert("Save Failed", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) {
                saveError = nil
            }
        } message: {
            Text(saveError ?? "Unable to save this image to Photos.")
        }
    }

    @ViewBuilder
    private func imagePreviewView(_ image: UIImage) -> some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemBackground))
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 18)

                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(
                            maxWidth: geometry.size.width - 28,
                            maxHeight: geometry.size.height - 120
                        )
                }
                .frame(
                    minWidth: geometry.size.width,
                    minHeight: geometry.size.height
                )
                .padding(.top, 64)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .ignoresSafeArea()
    }

    private var loadingState: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            ProgressView()
                .controlSize(.regular)
        }
        .ignoresSafeArea()
    }

    private var headerActions: some View {
        ZStack {
            Text(fileDisplayName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, 120)

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                if canSaveToPhotos {
                    Button {
                        Task { await saveImageToPhotos() }
                    } label: {
                        Group {
                            switch saveState {
                            case .idle:
                                Image(systemName: "arrow.down.to.line")
                                    .font(.system(size: 15, weight: .semibold))
                            case .saving:
                                ProgressView()
                                    .controlSize(.small)
                            case .saved:
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                            }
                        }
                        .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(saveState == .saved ? "Saved to Photos" : "Save to Photos")
                    .disabled(saveState == .saving)
                }

                Button {
                    isShowingShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Share")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    private var shareItems: [Any] {
        if let imagePreview {
            return [imagePreview.image]
        }
        return [fileURL]
    }

    @MainActor
    private func loadImagePreview() async {
        isLoadingPreview = true
        imagePreview = nil

        for attempt in 0..<4 {
            switch Self.loadImagePreview(from: fileURL) {
            case .image(let payload):
                imagePreview = payload
                isLoadingPreview = false
                return
            case .notImage:
                isLoadingPreview = false
                return
            case .unavailable:
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
            }
        }

        isLoadingPreview = false
    }

    @MainActor
    private func saveImageToPhotos() async {
        guard let imagePreview, canSaveToPhotos, saveState != .saving else { return }

        saveState = .saving

        let authorization = await requestPhotoAccess()
        guard authorization == .authorized || authorization == .limited else {
            saveState = .idle
            saveError = "Photo Library access is required to save images."
            return
        }

        do {
            try await PhotoLibraryImageSaver.saveImageData(
                imagePreview.data,
                originalFilename: fileURL.lastPathComponent
            )
            saveState = .saved

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if saveState == .saved {
                    saveState = .idle
                }
            }
        } catch {
            saveState = .idle
            saveError = error.localizedDescription
        }
    }

    private func requestPhotoAccess() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func loadImagePreview(from fileURL: URL) -> ImagePreviewLoadResult {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return .unavailable
        }

        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return .notImage
        }

        let contentType = inferredContentType(from: imageSource, fileURL: fileURL, data: data)
        guard contentType.conforms(to: .image) else {
            return .notImage
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(
            imageSource,
            0,
            [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary
        ) else {
            return .unavailable
        }

        return .image(
            ImagePreviewPayload(
                image: UIImage(cgImage: cgImage),
                data: data,
                contentType: contentType
            )
        )
    }

    private static func inferredContentType(from imageSource: CGImageSource, fileURL: URL, data: Data) -> UTType {
        if let typeIdentifier = CGImageSourceGetType(imageSource) as? String,
           let type = UTType(typeIdentifier) {
            return type
        }

        if let type = UTType(filenameExtension: fileURL.pathExtension) {
            return type
        }

        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return .png
        }

        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return .jpeg
        }

        if data.starts(with: Array("GIF8".utf8)) {
            return .gif
        }

        return .data
    }
}

private enum PhotoLibraryImageSaver {
    static func saveImageData(_ data: Data, originalFilename: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = originalFilename
                request.addResource(with: .photo, data: data, options: options)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoLibrarySaveError.unknown)
                }
            }
        }
    }
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private enum PhotoLibrarySaveError: LocalizedError {
    case unknown

    var errorDescription: String? {
        switch self {
        case .unknown:
            return "Unable to save this image to Photos."
        }
    }
}
