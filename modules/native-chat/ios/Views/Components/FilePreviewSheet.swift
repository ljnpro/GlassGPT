import Photos
import SwiftUI
import UIKit

struct FilePreviewSheet: View {
    let fileURL: URL

    @State private var saveState: SaveState = .idle
    @State private var saveError: String?
    @State private var previewImage: UIImage?

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        _previewImage = State(initialValue: Self.loadPreviewImage(from: fileURL))
    }

    private var canSaveToPhotos: Bool {
        previewImage != nil
    }

    private var fileDisplayName: String {
        let trimmed = fileURL.deletingPathExtension().lastPathComponent
        return trimmed.isEmpty ? fileURL.lastPathComponent : trimmed
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let previewImage {
                imagePreview(previewImage)
            } else {
                FilePreviewController(fileURL: fileURL)
                    .ignoresSafeArea()
            }

            if previewImage != nil {
                headerActions
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
            }
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
    private func imagePreview(_ image: UIImage) -> some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                ZStack {
                    Color.clear

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
                .padding(.bottom, 20)
            }
            .background(Color(uiColor: .secondarySystemBackground))
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
                                    .font(.system(size: 16, weight: .semibold))
                            case .saving:
                                ProgressView()
                                    .controlSize(.small)
                            case .saved:
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .bold))
                            }
                        }
                        .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(saveState == .saved ? "Saved to Photos" : "Save to Photos")
                    .disabled(saveState == .saving)
                }

                ShareLink(item: fileURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40)
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

    @MainActor
    private func saveImageToPhotos() async {
        guard let previewImage, canSaveToPhotos, saveState != .saving else { return }

        saveState = .saving

        let authorization = await requestPhotoAccess()
        guard authorization == .authorized || authorization == .limited else {
            saveState = .idle
            saveError = "Photo Library access is required to save images."
            return
        }

        do {
            try await PhotoLibraryImageSaver.saveImage(previewImage)
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

    private static func loadPreviewImage(from fileURL: URL) -> UIImage? {
        if let image = UIImage(contentsOfFile: fileURL.path) {
            return image
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return UIImage(data: data)
    }
}

private enum PhotoLibraryImageSaver {
    static func saveImage(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
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

private enum PhotoLibrarySaveError: LocalizedError {
    case unknown

    var errorDescription: String? {
        switch self {
        case .unknown:
            return "Unable to save this image to Photos."
        }
    }
}
