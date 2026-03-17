import Foundation

/// Provides offline KaTeX rendering by loading bundled JS/CSS resources.
/// Falls back to CDN if bundle resources are unavailable.
@MainActor
enum KaTeXProvider {

    // MARK: - Cached Resources

    private static var _cachedCSS: String?
    private static var _cachedJS: String?
    private static var _bundleURL: URL?

    /// The base URL for resolving relative font paths in CSS.
    static var baseURL: URL? {
        if let cached = _bundleURL { return cached }
        // Find the Resources directory inside the NativeChat bundle
        if let resourceURL = findResourceDirectory() {
            _bundleURL = resourceURL
            return resourceURL
        }
        return nil
    }

    /// Inline CSS content from the bundled katex.min.css.
    static var cssContent: String? {
        if let cached = _cachedCSS { return cached }
        guard let url = findResource(named: "katex.min", ext: "css") else { return nil }
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            Loggers.app.debug("[KaTeXProvider.cssContent] \(error.localizedDescription)")
            return nil
        }
        _cachedCSS = content
        return content
    }

    /// Inline JS content from the bundled katex.min.js.
    static var jsContent: String? {
        if let cached = _cachedJS { return cached }
        guard let url = findResource(named: "katex.min", ext: "js") else { return nil }
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            Loggers.app.debug("[KaTeXProvider.jsContent] \(error.localizedDescription)")
            return nil
        }
        _cachedJS = content
        return content
    }

    /// Whether offline KaTeX resources are available.
    static var isAvailable: Bool {
        return cssContent != nil && jsContent != nil
    }
}
