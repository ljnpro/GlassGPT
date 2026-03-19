import ChatUIComponents
import SwiftUI
@preconcurrency import WebKit

// MARK: - Block LaTeX View

/// Renders a block-level LaTeX expression using a WKWebView backed by KaTeX.
package struct BlockLaTeXView: View {
    let latex: String

    @State private var height: CGFloat = 44
    @State private var availableWidth: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    package var body: some View {
        BlockLaTeXWebView(
            latex: latex,
            isDark: colorScheme == .dark,
            availableWidth: availableWidth,
            displayScale: max(displayScale, 1),
            height: $height
        )
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .center)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        updateAvailableWidth(geometry.size.width)
                    }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        updateAvailableWidth(newWidth)
                    }
            }
        }
        .clipped()
    }

    private func updateAvailableWidth(_ newWidth: CGFloat) {
        let screenScale = max(displayScale, 1)
        let roundedWidth = max((newWidth * screenScale).rounded(.down) / screenScale, 0)
        guard abs(availableWidth - roundedWidth) > 0.5 else { return }
        availableWidth = roundedWidth
    }
}

/// Wraps ``BlockLaTeXView`` in a standalone glass surface card.
package struct StandaloneBlockLaTeXCardView: View {
    let latex: String

    package var body: some View {
        BlockLaTeXView(latex: latex)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .singleSurfaceGlass(
                cornerRadius: 18,
                stableFillOpacity: 0.008,
                tintOpacity: 0.022,
                borderWidth: 0.8,
                darkBorderOpacity: 0.15,
                lightBorderOpacity: 0.085
            )
    }
}

// MARK: - Block LaTeX WKWebView Wrapper

@MainActor
struct BlockLaTeXWebView: UIViewRepresentable {
    let latex: String
    let isDark: Bool
    let availableWidth: CGFloat
    let displayScale: CGFloat
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height, displayScale: displayScale)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "sizeCallback")
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.lastKey = ""

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard availableWidth > 1 else { return }
        context.coordinator.displayScale = max(displayScale, 1)

        let pixelWidth = Int((availableWidth * max(displayScale, 1)).rounded(.toNearestOrEven))
        let key = "\(latex)-\(isDark)-\(pixelWidth)"
        guard key != context.coordinator.lastKey else { return }
        context.coordinator.lastKey = key
        context.coordinator.cacheKey = key

        if let cachedHeight = LaTeXMeasurementState.cachedHeights[key] {
            Task { @MainActor in
                if abs(height - cachedHeight) > 0.5 {
                    height = cachedHeight
                }
            }
        }

        let token = UUID().uuidString
        context.coordinator.expectedMeasurementToken = token

        let result = KaTeXProvider.htmlForLatex(
            latex,
            isDark: isDark,
            measurementToken: token,
            maxWidth: availableWidth
        )
        webView.loadHTMLString(result.html, baseURL: result.baseURL)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "sizeCallback")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var height: CGFloat
        var displayScale: CGFloat
        var lastKey: String = ""
        var cacheKey: String = ""
        var expectedMeasurementToken: String = ""

        init(height: Binding<CGFloat>, displayScale: CGFloat) {
            _height = height
            self.displayScale = displayScale
        }

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            Task { @MainActor in
                guard let payload = message.body as? [String: NSObject],
                      let token = payload["token"] as? NSString
                else {
                    return
                }

                let newHeight: CGFloat
                if let value = payload["height"] as? NSNumber {
                    newHeight = max(CGFloat(truncating: value), 20)
                } else {
                    return
                }

                guard token as String == self.expectedMeasurementToken else { return }

                let screenScale = max(self.displayScale, 1)
                let roundedHeight = max((newHeight * screenScale).rounded(.up) / screenScale, 20)
                guard roundedHeight < 4096 else { return }

                LaTeXMeasurementState.cachedHeights[self.cacheKey] = roundedHeight

                if abs(self.height - roundedHeight) > 0.5 {
                    self.height = roundedHeight
                }
            }
        }
    }
}

@MainActor
enum LaTeXMeasurementState {
    static var cachedHeights: [String: CGFloat] = [:]
}
