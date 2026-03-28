import ChatDomain
import ChatUIComponents
import FilePreviewSupport
import GeneratedFilesCore
import SwiftUI
import UIKit

/// Full-screen preview sheet for generated images and PDFs, with save-to-photos and share actions.
public struct FilePreviewSheet: View {
    struct StateSeed {
        var saveState: GeneratedFilePreviewSaveState = .idle
        var saveError: String?
        var imagePreviewState: GeneratedImagePreviewState = .loading
        var pdfPreviewState: GeneratedPDFPreviewState = .loading
        var showSaveSuccessHUD = false
        var isShowingShareSheet = false
    }

    let previewItem: FilePreviewItem
    var isDismissPending = false
    var onBeginDismissInteraction: () -> Void = {}
    var onRequestDismiss: () -> Void = {}

    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.hapticsEnabled) var hapticsEnabled

    @State var saveState: GeneratedFilePreviewSaveState = .idle
    @State var saveError: String?
    @State var imagePreviewState: GeneratedImagePreviewState = .loading
    @State var pdfPreviewState: GeneratedPDFPreviewState = .loading
    @State var showSaveSuccessHUD = false
    @State var saveSuccessHUDToken = UUID()
    @State var isShowingShareSheet = false

    var fileURL: URL {
        previewItem.url
    }

    var hapticService: HapticService {
        .shared
    }

    var canSaveToPhotos: Bool {
        imagePreviewPayload != nil
    }

    var imagePreviewPayload: GeneratedImagePreviewPayload? {
        if case let .image(payload) = imagePreviewState {
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

    /// The full-screen preview content for the current generated file.
    public var body: some View {
        content
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("filePreview.root")
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
            .alert(String(localized: "Save Failed"), isPresented: saveErrorBinding) {
                Button(String(localized: "OK"), role: .cancel) {
                    saveError = nil
                }
            } message: {
                Text(saveError ?? String(localized: "Unable to save this image to Photos."))
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

    /// Creates a file preview sheet for the given item with optional dismiss callbacks.
    public init(
        previewItem: FilePreviewItem,
        isDismissPending: Bool = false,
        onBeginDismissInteraction: @escaping () -> Void = {},
        onRequestDismiss: @escaping () -> Void = {}
    ) {
        self.init(
            previewItem: previewItem,
            isDismissPending: isDismissPending,
            onBeginDismissInteraction: onBeginDismissInteraction,
            onRequestDismiss: onRequestDismiss,
            stateSeed: StateSeed()
        )
    }

    init(
        previewItem: FilePreviewItem,
        isDismissPending: Bool = false,
        onBeginDismissInteraction: @escaping () -> Void = {},
        onRequestDismiss: @escaping () -> Void = {},
        stateSeed: StateSeed
    ) {
        self.previewItem = previewItem
        self.isDismissPending = isDismissPending
        self.onBeginDismissInteraction = onBeginDismissInteraction
        self.onRequestDismiss = onRequestDismiss
        _saveState = State(initialValue: stateSeed.saveState)
        _saveError = State(initialValue: stateSeed.saveError)
        _imagePreviewState = State(initialValue: stateSeed.imagePreviewState)
        _pdfPreviewState = State(initialValue: stateSeed.pdfPreviewState)
        _showSaveSuccessHUD = State(initialValue: stateSeed.showSaveSuccessHUD)
        _isShowingShareSheet = State(initialValue: stateSeed.isShowingShareSheet)
    }
}
