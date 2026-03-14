import Photos
import SwiftUI
import UniformTypeIdentifiers

struct FilePreviewSheet: View {
    let fileURL: URL

    @State private var saveState: SaveState = .idle
    @State private var saveError: String?

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
    }

    private var canSaveToPhotos: Bool {
        guard let fileType = UTType(filenameExtension: fileURL.pathExtension) else {
            return false
        }

        return fileType.conforms(to: .image)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            FilePreviewController(fileURL: fileURL)
                .ignoresSafeArea()

            if canSaveToPhotos {
                saveButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 28)
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

    private var saveButton: some View {
        Button {
            Task { await saveImageToPhotos() }
        } label: {
            Group {
                switch saveState {
                case .idle:
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 18, weight: .semibold))
                case .saving:
                    ProgressView()
                        .controlSize(.small)
                case .saved:
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                }
            }
            .frame(width: 52, height: 52)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(saveState == .saved ? "Saved to Photos" : "Save to Photos")
        .disabled(saveState == .saving)
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    @MainActor
    private func saveImageToPhotos() async {
        guard canSaveToPhotos, saveState != .saving else { return }

        saveState = .saving

        let authorization = await requestPhotoAccess()
        guard authorization == .authorized || authorization == .limited else {
            saveState = .idle
            saveError = "Photo Library access is required to save images."
            return
        }

        do {
            try await PhotoLibraryImageSaver.saveImage(at: fileURL)
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
}

private enum PhotoLibraryImageSaver {
    static func saveImage(at fileURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = fileURL.lastPathComponent
                request.addResource(with: .photo, fileURL: fileURL, options: options)
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
