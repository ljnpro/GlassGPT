import ImageIO
import PDFKit
import Photos
import SwiftUI
import UIKit

struct FilePreviewSheet: View {
    let previewItem: FilePreviewItem
    var onWillDismiss: () -> Void = {}

    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var saveState: SaveState = .idle
    @State private var saveError: String?
    @State private var imagePreviewState: ImagePreviewState = .loading
    @State private var pdfPreviewState: PDFPreviewState = .loading
    @State private var showSaveSuccessHUD = false
    @State private var saveSuccessHUDToken = UUID()
    @State private var isShowingShareSheet = false
    @State private var isDismissingPreview = false

    private struct ImagePreviewPayload {
        let image: UIImage
        let data: Data
    }

    private enum ImagePreviewState {
        case loading
        case image(ImagePreviewPayload)
        case error(String)
    }

    private enum ImagePreviewLoadResult {
        case image(ImagePreviewPayload)
        case error(String)
        case unavailable
    }

    private enum PDFPreviewState {
        case loading
        case document(PDFDocument)
        case error(String)
    }

    private enum PDFPreviewLoadResult {
        case document(PDFDocument)
        case error(String)
        case unavailable
    }

    private enum SaveState: Equatable {
        case idle
        case saving
    }

    private var fileURL: URL {
        previewItem.url
    }

    private var canSaveToPhotos: Bool {
        imagePreviewPayload != nil
    }

    private var imagePreviewPayload: ImagePreviewPayload? {
        if case .image(let payload) = imagePreviewState {
            return payload
        }
        return nil
    }

    private var isDarkAppearance: Bool {
        resolvedColorScheme == .dark
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    private var resolvedColorScheme: ColorScheme {
        selectedTheme.colorScheme ?? colorScheme
    }

    private var viewerBackgroundColor: Color {
        isDarkAppearance ? .black : .white
    }

    private var viewerPrimaryColor: Color {
        isDarkAppearance ? .white : .black
    }

    private var viewerSecondaryColor: Color {
        isDarkAppearance ? Color.white.opacity(0.72) : Color.black.opacity(0.58)
    }

    private var actionIconSize: CGFloat {
        isPad ? 22 : 20
    }

    private var closeIconSize: CGFloat {
        isPad ? 23 : 21
    }

    private var imageTopBarSideClearance: CGFloat {
        isPad ? 116 : 104
    }

    private var pdfTopBarSideClearance: CGFloat {
        isPad ? 176 : 156
    }

    private var bottomButtonControlSize: ControlSize {
        .large
    }

    private var topButtonControlSize: ControlSize {
        .large
    }

    var body: some View {
        content
            .preferredColorScheme(selectedTheme.colorScheme)
            .task(id: previewItem.id) {
                await loadPreview()
            }
            .sheet(isPresented: $isShowingShareSheet) {
                ActivityViewController(activityItems: [fileURL])
            }
            .alert("Save Failed", isPresented: saveErrorBinding) {
                Button("OK", role: .cancel) {
                    saveError = nil
                }
            } message: {
                Text(saveError ?? "Unable to save this image to Photos.")
            }
            .overlay {
                if isDismissingPreview {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .accessibilityHidden(true)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch previewItem.kind {
        case .generatedImage:
            generatedImageViewer
        case .generatedPDF:
            generatedPDFViewer
        }
    }

    private var generatedImageViewer: some View {
        ZStack {
            viewerBackgroundColor
                .ignoresSafeArea()

            GeometryReader { geometry in
                generatedImageCanvas(in: geometry)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            imageTopBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            imageBottomBar
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
        }
        .overlay {
            GeometryReader { geometry in
                if showSaveSuccessHUD {
                    saveSuccessHUD
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 72)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var generatedPDFViewer: some View {
        ZStack {
            viewerBackgroundColor
                .ignoresSafeArea()

            GeometryReader { geometry in
                generatedPDFCanvas(in: geometry)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            pdfTopBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func generatedImageCanvas(in geometry: GeometryProxy) -> some View {
        switch imagePreviewState {
        case .loading:
            viewerStateContainer {
                ProgressView()
                    .controlSize(.regular)
                    .tint(viewerPrimaryColor)
            }
        case .image(let payload):
            imagePreviewView(payload.image, in: geometry)
        case .error(let message):
            viewerStateContainer {
                VStack(spacing: 14) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(viewerSecondaryColor)

                    Text(message)
                        .font(.body)
                        .foregroundStyle(viewerSecondaryColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
    }

    @ViewBuilder
    private func generatedPDFCanvas(in geometry: GeometryProxy) -> some View {
        switch pdfPreviewState {
        case .loading:
            viewerStateContainer {
                ProgressView()
                    .controlSize(.regular)
                    .tint(viewerPrimaryColor)
            }
        case .document(let document):
            pdfPreviewView(document, in: geometry)
        case .error(let message):
            viewerStateContainer {
                VStack(spacing: 14) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(viewerSecondaryColor)

                    Text(message)
                        .font(.body)
                        .foregroundStyle(viewerSecondaryColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
    }

    private func imagePreviewView(_ image: UIImage, in geometry: GeometryProxy) -> some View {
        let verticalPadding: CGFloat = isPad ? 24 : 16
        let availableHeight = max(geometry.size.height - (verticalPadding * 2), 1)
        let horizontalPadding: CGFloat = isPad ? 32 : 16
        let availableWidth = max(geometry.size.width - (horizontalPadding * 2), 1)
        let maxImageWidth = isPad ? min(availableWidth, geometry.size.width * 0.74) : availableWidth

        return ScrollView([.horizontal, .vertical], showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(maxWidth: maxImageWidth, maxHeight: availableHeight)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: availableHeight,
                        maxHeight: availableHeight,
                        alignment: .center
                    )
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                Spacer(minLength: 0)
            }
            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
        }
    }

    private func pdfPreviewView(_ document: PDFDocument, in geometry: GeometryProxy) -> some View {
        let horizontalPadding: CGFloat = isPad ? 24 : 8
        let verticalPadding: CGFloat = isPad ? 20 : 8
        let availableWidth = max(geometry.size.width - (horizontalPadding * 2), 1)
        let maxViewerWidth = isPad ? min(availableWidth, geometry.size.width * 0.72) : availableWidth

        return GeneratedPDFView(document: document, isDarkAppearance: isDarkAppearance)
            .frame(maxWidth: maxViewerWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
    }

    private func viewerStateContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var imageTopBar: some View {
        ZStack {
            titleText
                .padding(.horizontal, imageTopBarSideClearance)

            HStack(spacing: 0) {
                Spacer()
                closeButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var pdfTopBar: some View {
        ZStack {
            titleText
                .padding(.horizontal, pdfTopBarSideClearance)

            HStack(spacing: 0) {
                pdfShareButton
                Spacer()
                closeButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var titleText: some View {
        Text(previewItem.viewerFilename)
            .font(.system(size: isPad ? 20 : 18, weight: .semibold))
            .foregroundStyle(viewerPrimaryColor)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
            .truncationMode(.middle)
    }

    private var imageBottomBar: some View {
        HStack {
            downloadButton

            Spacer(minLength: 0)

            bottomShareButton
        }
    }

    private var closeButton: some View {
        Button {
            guard !isDismissingPreview else { return }
            isDismissingPreview = true
            onWillDismiss()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000)
                dismiss()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: closeIconSize, weight: .semibold))
                .frame(width: closeIconSize, height: closeIconSize)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(topButtonControlSize)
        .accessibilityLabel("Close preview")
        .disabled(isDismissingPreview)
    }

    private var downloadButton: some View {
        Button {
            Task { await saveImageToPhotos() }
        } label: {
            switch saveState {
            case .idle:
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: actionIconSize, weight: .semibold))
                    .frame(width: actionIconSize, height: actionIconSize)
            case .saving:
                ProgressView()
                    .controlSize(.small)
                    .tint(viewerPrimaryColor)
                    .frame(width: actionIconSize, height: actionIconSize)
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(bottomButtonControlSize)
        .accessibilityLabel("Download to Photos")
        .disabled(saveState == .saving || !canSaveToPhotos)
        .opacity((saveState == .saving || !canSaveToPhotos) ? 0.62 : 1)
    }

    private var bottomShareButton: some View {
        Button {
            presentShareSheet()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: actionIconSize, weight: .semibold))
                .frame(width: actionIconSize, height: actionIconSize)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(bottomButtonControlSize)
        .accessibilityLabel("Share")
    }

    private var pdfShareButton: some View {
        Button {
            presentShareSheet()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: actionIconSize, weight: .semibold))
                .frame(width: actionIconSize, height: actionIconSize)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(topButtonControlSize)
        .accessibilityLabel("Share")
    }

    private var saveSuccessHUD: some View {
        Label("Saved to Photos", systemImage: "checkmark.circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(viewerPrimaryColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .singleSurfaceGlass(
                cornerRadius: 999,
                stableFillOpacity: 0.012,
                borderWidth: 0.8,
                darkBorderOpacity: 0.14,
                lightBorderOpacity: 0.08
            )
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    @MainActor
    private func loadPreview() async {
        switch previewItem.kind {
        case .generatedImage:
            await loadImagePreview()
        case .generatedPDF:
            await loadPDFPreview()
        }
    }

    @MainActor
    private func loadImagePreview() async {
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
                    try? await Task.sleep(nanoseconds: 150_000_000)
                } else {
                    imagePreviewState = .error("This generated image could not be loaded.")
                }
            }
        }
    }

    @MainActor
    private func loadPDFPreview() async {
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
                    try? await Task.sleep(nanoseconds: 150_000_000)
                } else {
                    pdfPreviewState = .error("This generated PDF could not be loaded.")
                }
            }
        }
    }

    @MainActor
    private func saveImageToPhotos() async {
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

    private func requestPhotoAccess() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func loadGeneratedImagePreview(from fileURL: URL) -> ImagePreviewLoadResult {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return .unavailable
        }

        guard FileDownloadService.isGeneratedImageFilename(fileURL.lastPathComponent) else {
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

    private static func loadGeneratedPDFPreview(from fileURL: URL) -> PDFPreviewLoadResult {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return .unavailable
        }

        guard FileDownloadService.isGeneratedPDFFilename(fileURL.lastPathComponent) else {
            return .error("This file is no longer recognized as a PDF.")
        }

        guard let document = PDFDocument(data: data) else {
            return .error("This generated PDF could not be rendered.")
        }

        return .document(document)
    }

    private func presentShareSheet() {
        isShowingShareSheet = true
    }

    private func showSaveSuccessFeedback() {
        let token = UUID()
        saveSuccessHUDToken = token

        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            showSaveSuccessHUD = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)

            guard saveSuccessHUDToken == token else { return }

            withAnimation(.easeInOut(duration: 0.2)) {
                showSaveSuccessHUD = false
            }
        }
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

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct GeneratedPDFView: UIViewRepresentable {
    let document: PDFDocument
    let isDarkAppearance: Bool

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.autoScales = true
        pdfView.usePageViewController(false)
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = UIColor(isDarkAppearance ? .black : .white)
        pdfView.document = document
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
        pdfView.backgroundColor = UIColor(isDarkAppearance ? .black : .white)
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
