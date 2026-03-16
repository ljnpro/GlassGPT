import PDFKit
import SwiftUI
import UIKit

extension FilePreviewSheet {
    @ViewBuilder
    func generatedImageCanvas(in geometry: GeometryProxy) -> some View {
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
    func generatedPDFCanvas(in geometry: GeometryProxy) -> some View {
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

    func imagePreviewView(_ image: UIImage, in geometry: GeometryProxy) -> some View {
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

    func pdfPreviewView(_ document: PDFDocument, in geometry: GeometryProxy) -> some View {
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

    func viewerStateContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    var imageTopBar: some View {
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

    var pdfTopBar: some View {
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

    var titleText: some View {
        Text(previewItem.viewerFilename)
            .font(.system(size: isPad ? 20 : 18, weight: .semibold))
            .foregroundStyle(viewerPrimaryColor)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
            .truncationMode(.middle)
    }

    var imageBottomBar: some View {
        HStack {
            downloadButton

            Spacer(minLength: 0)

            bottomShareButton
        }
    }

    var closeButton: some View {
        PreviewActionButton(
            diameter: circularButtonDiameter,
            isEnabled: !isDismissPending,
            accessibilityLabel: "Close preview",
            onTriggerStart: onBeginDismissInteraction,
            action: onRequestDismiss
        ) {
            Image(systemName: "xmark")
                .font(.system(size: closeIconSize, weight: .semibold))
                .foregroundStyle(viewerPrimaryColor)
        }
    }

    var downloadButton: some View {
        PreviewActionButton(
            diameter: circularButtonDiameter,
            isEnabled: !isDismissPending && saveState != .saving && canSaveToPhotos,
            accessibilityLabel: "Download to Photos",
            action: {
                Task { await saveImageToPhotos() }
            }
        ) {
            switch saveState {
            case .idle:
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: actionIconSize, weight: .semibold))
                    .foregroundStyle(viewerPrimaryColor)
            case .saving:
                ProgressView()
                    .controlSize(.small)
                    .tint(viewerPrimaryColor)
            }
        }
    }

    var bottomShareButton: some View {
        PreviewActionButton(
            diameter: circularButtonDiameter,
            isEnabled: !isDismissPending,
            accessibilityLabel: "Share",
            action: presentShareSheet
        ) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: actionIconSize, weight: .semibold))
                .foregroundStyle(viewerPrimaryColor)
        }
    }

    var pdfShareButton: some View {
        PreviewActionButton(
            diameter: circularButtonDiameter,
            isEnabled: !isDismissPending,
            accessibilityLabel: "Share",
            action: presentShareSheet
        ) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: actionIconSize, weight: .semibold))
                .foregroundStyle(viewerPrimaryColor)
        }
    }

    var saveSuccessHUD: some View {
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

    var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }
}
