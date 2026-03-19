import Foundation

@MainActor
/// Provides cached access to bundled KaTeX CSS and JavaScript resources for offline LaTeX rendering.
public enum KaTeXProvider {
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

        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
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

        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            return nil
        }

        cachedJS = content
        return content
    }

    static var isAvailable: Bool {
        cssContent != nil && jsContent != nil
    }
}
