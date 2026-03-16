import ImageIO
import PDFKit
import Photos
import SwiftUI
import UIKit

struct FilePreviewSheet: View {
    let previewItem: FilePreviewItem
    var isDismissPending: Bool = false
    var onBeginDismissInteraction: () -> Void = {}
    var onRequestDismiss: () -> Void = {}

    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    @State var saveState: SaveState = .idle
    @State var saveError: String?
    @State var imagePreviewState: ImagePreviewState = .loading
    @State var pdfPreviewState: PDFPreviewState = .loading
    @State var showSaveSuccessHUD = false
    @State var saveSuccessHUDToken = UUID()
    @State var isShowingShareSheet = false

    struct ImagePreviewPayload {
        let image: UIImage
        let data: Data
    }

    enum ImagePreviewState {
        case loading
        case image(ImagePreviewPayload)
        case error(String)
    }

    enum ImagePreviewLoadResult {
        case image(ImagePreviewPayload)
        case error(String)
        case unavailable
    }

    enum PDFPreviewState {
        case loading
        case document(PDFDocument)
        case error(String)
    }

    enum PDFPreviewLoadResult {
        case document(PDFDocument)
        case error(String)
        case unavailable
    }

    enum SaveState: Equatable {
        case idle
        case saving
    }

    struct PreviewActionButton<Label: View>: View {
        let diameter: CGFloat
        let isEnabled: Bool
        let accessibilityLabel: String
        var onTriggerStart: () -> Void = {}
        let action: () -> Void
        @ViewBuilder let label: () -> Label

        @State private var isPressed = false

        private var hitBounds: CGRect {
            CGRect(x: 0, y: 0, width: diameter, height: diameter)
        }

        var body: some View {
            label()
                .frame(width: diameter, height: diameter)
                .singleFrameGlassCircleControl(
                    tintOpacity: 0.015,
                    borderWidth: 0.78,
                    darkBorderOpacity: 0.14,
                    lightBorderOpacity: 0.08
                )
                .scaleEffect(isPressed ? 0.9 : 1)
                .opacity(isEnabled ? (isPressed ? 0.8 : 1) : 0.62)
                .animation(.spring(response: 0.18, dampingFraction: 0.82), value: isPressed)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isEnabled else { return }
                            isPressed = hitBounds.contains(value.location)
                        }
                        .onEnded { value in
                            let shouldTrigger = isEnabled && hitBounds.contains(value.location)
                            withAnimation(.spring(response: 0.18, dampingFraction: 0.82)) {
                                isPressed = false
                            }

                            guard shouldTrigger else { return }
                            onTriggerStart()
                            Task { @MainActor in
                                do {
                                    try await Task.sleep(nanoseconds: 55_000_000)
                                } catch {
                                    return
                                }
                                action()
                            }
                        }
                )
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text(accessibilityLabel))
                .accessibilityAction {
                    guard isEnabled else { return }
                    action()
                }
        }
    }

    var fileURL: URL {
        previewItem.url
    }

    var canSaveToPhotos: Bool {
        imagePreviewPayload != nil
    }

    var imagePreviewPayload: ImagePreviewPayload? {
        if case .image(let payload) = imagePreviewState {
            return payload
        }
        return nil
    }

    var isDarkAppearance: Bool {
        resolvedColorScheme == .dark
    }

    var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    var resolvedColorScheme: ColorScheme {
        selectedTheme.colorScheme ?? colorScheme
    }

    var viewerBackgroundColor: Color {
        isDarkAppearance ? .black : .white
    }

    var viewerPrimaryColor: Color {
        isDarkAppearance ? .white : .black
    }

    var viewerSecondaryColor: Color {
        isDarkAppearance ? Color.white.opacity(0.72) : Color.black.opacity(0.58)
    }

    var actionIconSize: CGFloat {
        isPad ? 22 : 20
    }

    var closeIconSize: CGFloat {
        isPad ? 23 : 21
    }

    var circularButtonDiameter: CGFloat {
        isPad ? 48 : 44
    }

    var imageTopBarSideClearance: CGFloat {
        isPad ? 116 : 104
    }

    var pdfTopBarSideClearance: CGFloat {
        isPad ? 176 : 156
    }

    var body: some View {
        content
            .scaleEffect(isDismissPending ? 0.986 : 1)
            .opacity(isDismissPending ? 0.9 : 1)
            .animation(.easeInOut(duration: 0.12), value: isDismissPending)
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
                if isDismissPending {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .accessibilityHidden(true)
                }
            }
    }

    @ViewBuilder
    var content: some View {
        switch previewItem.kind {
        case .generatedImage:
            generatedImageViewer
        case .generatedPDF:
            generatedPDFViewer
        }
    }

    var generatedImageViewer: some View {
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

    var generatedPDFViewer: some View {
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
}
