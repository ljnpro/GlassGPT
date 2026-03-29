import Foundation
import OSLog

/// Provides cached access to bundled KaTeX CSS and JavaScript resources for offline LaTeX rendering.
@MainActor
public enum KaTeXProvider {
    static let logger = Logger(subsystem: "GlassGPT", category: "chat")
    private static var cachedCSS: String?
    private static var cachedJS: String?
    private static var cachedBundleURL: URL?

    static var baseURL: URL? {
        if let cachedBundleURL {
            return cachedBundleURL
        }

        if let resourceURL = findResourceDirectory() {
            cachedBundleURL = resourceURL
            return resourceURL
        }

        return nil
    }

    static var cssContent: String? {
        if let cachedCSS {
            return cachedCSS
        }

        guard let url = findResource(named: "katex.min", ext: "css") else {
            return nil
        }

        guard let content = loadContent(from: url) else {
            return nil
        }

        cachedCSS = content
        return content
    }

    static var jsContent: String? {
        if let cachedJS {
            return cachedJS
        }

        guard let url = findResource(named: "katex.min", ext: "js") else {
            return nil
        }

        guard let content = loadContent(from: url) else {
            return nil
        }

        cachedJS = content
        return content
    }

    static var isAvailable: Bool {
        cssContent != nil && jsContent != nil
    }

    package static func loadContent(
        from url: URL,
        onFailure: ((String) -> Void)? = nil,
        logFailure: Bool = true
    ) -> String? {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            let message = "Failed to load KaTeX resource at \(url.path): \(error.localizedDescription)"
            onFailure?(message)
            if logFailure {
                logger.error("\(message, privacy: .public)")
            }
            return nil
        }
    }
}
