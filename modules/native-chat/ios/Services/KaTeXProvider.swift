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
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        _cachedCSS = content
        return content
    }

    /// Inline JS content from the bundled katex.min.js.
    static var jsContent: String? {
        if let cached = _cachedJS { return cached }
        guard let url = findResource(named: "katex.min", ext: "js") else { return nil }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        _cachedJS = content
        return content
    }

    /// Whether offline KaTeX resources are available.
    static var isAvailable: Bool {
        return cssContent != nil && jsContent != nil
    }

    // MARK: - HTML Generation

    /// Generate a complete HTML document for rendering a LaTeX expression.
    static func htmlForLatex(_ latex: String, isDark: Bool) -> (html: String, baseURL: URL?) {
        let textColor = isDark ? "#e5e5e5" : "#1c1c1e"

        let encoder = JSONEncoder()
        let jsonLatex: String
        if let jsonData = try? encoder.encode(latex),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            jsonLatex = jsonString
        } else {
            let escaped = latex
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            jsonLatex = "\"\(escaped)\""
        }

        if isAvailable, let css = cssContent, let js = jsContent {
            // Offline mode: inline CSS and JS
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>\(css)</style>
            <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                background: transparent;
                color: \(textColor);
                font-size: 17px;
                display: flex;
                align-items: center;
                justify-content: center;
                min-height: 20px;
                padding: 0;
                margin: 0;
                -webkit-text-size-adjust: none;
            }
            .katex { font-size: 1em !important; }
            .katex-display { margin: 0 !important; }
            #math { display: inline-block; max-width: 100%; overflow-x: auto; }
            </style>
            </head>
            <body>
            <div id="math"></div>
            <script>\(js)</script>
            <script>
            (function() {
                var latexStr = \(jsonLatex);
                try {
                    katex.render(latexStr, document.getElementById('math'), {
                        displayMode: true,
                        throwOnError: false,
                        trust: true,
                        strict: false
                    });
                } catch(e) {
                    document.getElementById('math').textContent = latexStr;
                }
                setTimeout(function() {
                    var h = document.body.scrollHeight;
                    if (h > 0) {
                        window.webkit.messageHandlers.sizeCallback.postMessage(h);
                    }
                }, 50);
            })();
            </script>
            </body>
            </html>
            """
            return (html, baseURL)
        } else {
            // Fallback: CDN mode
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css" crossorigin="anonymous">
            <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js" crossorigin="anonymous"></script>
            <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                background: transparent;
                color: \(textColor);
                font-size: 17px;
                display: flex;
                align-items: center;
                justify-content: center;
                min-height: 20px;
                padding: 0;
                margin: 0;
                -webkit-text-size-adjust: none;
            }
            .katex { font-size: 1em !important; }
            .katex-display { margin: 0 !important; }
            #math { display: inline-block; max-width: 100%; overflow-x: auto; }
            </style>
            </head>
            <body>
            <div id="math"></div>
            <script>
            document.addEventListener('DOMContentLoaded', function() {
                var latexStr = \(jsonLatex);
                try {
                    katex.render(latexStr, document.getElementById('math'), {
                        displayMode: true,
                        throwOnError: false,
                        trust: true,
                        strict: false
                    });
                } catch(e) {
                    document.getElementById('math').textContent = latexStr;
                }
                setTimeout(function() {
                    var h = document.body.scrollHeight;
                    if (h > 0) {
                        window.webkit.messageHandlers.sizeCallback.postMessage(h);
                    }
                }, 100);
            });
            </script>
            </body>
            </html>
            """
            return (html, URL(string: "https://cdn.jsdelivr.net"))
        }
    }

    // MARK: - Resource Lookup

    private static func findResourceDirectory() -> URL? {
        // Search through all bundles for the Resources directory containing KaTeX files
        let allBundles = Bundle.allBundles + [Bundle.main]
        for bundle in allBundles {
            // Check for resources directly in bundle
            if let cssURL = bundle.url(forResource: "katex.min", withExtension: "css") {
                return cssURL.deletingLastPathComponent()
            }
            // Check in Resources subdirectory
            if let resourcePath = bundle.resourcePath {
                let resourcesDir = URL(fileURLWithPath: resourcePath).appendingPathComponent("Resources")
                let cssPath = resourcesDir.appendingPathComponent("katex.min.css")
                if FileManager.default.fileExists(atPath: cssPath.path) {
                    return resourcesDir
                }
            }
        }

        // Also check the pod bundle path pattern
        if let podBundle = Bundle(identifier: "org.cocoapods.NativeChat") {
            if let cssURL = podBundle.url(forResource: "katex.min", withExtension: "css") {
                return cssURL.deletingLastPathComponent()
            }
        }

        return nil
    }

    private static func findResource(named name: String, ext: String) -> URL? {
        let allBundles = Bundle.allBundles + [Bundle.main]
        for bundle in allBundles {
            if let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
            // Check in Resources subdirectory
            if let resourcePath = bundle.resourcePath {
                let path = URL(fileURLWithPath: resourcePath)
                    .appendingPathComponent("Resources")
                    .appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: path.path) {
                    return path
                }
            }
        }
        return nil
    }
}
