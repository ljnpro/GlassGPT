import Foundation

extension KaTeXProvider {
    /// Generates a self-contained HTML page that renders the given LaTeX string using KaTeX.
    ///
    /// Falls back to CDN-hosted KaTeX when offline bundle resources are unavailable.
    public static func htmlForLatex(
        _ latex: String,
        isDark: Bool,
        measurementToken: String,
        maxWidth: CGFloat
    ) -> (html: String, baseURL: URL?) {
        let textColor = isDark ? "#e5e5e5" : "#1c1c1e"
        let clampedMaxWidth = max(Int(maxWidth.rounded(.down)), 1)
        let jsonLatex = encodedLatexString(latex)

        if isAvailable, let css = cssContent, let js = jsContent {
            return (
                offlineHTML(
                    css: css,
                    js: js,
                    textColor: textColor,
                    clampedMaxWidth: clampedMaxWidth,
                    jsonLatex: jsonLatex,
                    measurementToken: measurementToken
                ),
                baseURL
            )
        }

        return (
            cdnHTML(
                textColor: textColor,
                clampedMaxWidth: clampedMaxWidth,
                jsonLatex: jsonLatex,
                measurementToken: measurementToken
            ),
            URL(string: "https://cdn.jsdelivr.net")
        )
    }

    private static func encodedLatexString(_ latex: String) -> String {
        let encodedResult = Result { try JSONEncoder().encode(latex) }
        if case let .success(data) = encodedResult,
           let json = String(data: data, encoding: .utf8) {
            return json
        }

        let escaped = latex
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    // swiftlint:disable:next function_body_length
    private static func offlineHTML(
        css: String,
        js: String,
        textColor: String,
        clampedMaxWidth: Int,
        jsonLatex: String,
        measurementToken: String
    ) -> String {
        """
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
            width: 100%;
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
        #math { display: inline-block; max-width: min(100%, \(clampedMaxWidth)px); overflow-x: auto; }
        </style>
        </head>
        <body>
        <div id="math"></div>
        <script>\(js)</script>
        <script>
        (function() {
            var latexStr = \(jsonLatex);
            var token = "\(measurementToken)";
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
            function reportHeight() {
                var node = document.getElementById('math');
                var h = node ? Math.ceil(node.getBoundingClientRect().height) : 0;
                if (h > 0) {
                    window.webkit.messageHandlers.sizeCallback.postMessage({ token: token, height: h });
                }
            }
            reportHeight();
            setTimeout(reportHeight, 50);
            setTimeout(reportHeight, 150);
            setTimeout(reportHeight, 400);
            if (typeof ResizeObserver !== 'undefined') {
                var ro = new ResizeObserver(function() { reportHeight(); });
                ro.observe(document.getElementById('math'));
            }
        })();
        </script>
        </body>
        </html>
        """
    }

    // swiftlint:disable:next function_body_length
    private static func cdnHTML(
        textColor: String,
        clampedMaxWidth: Int,
        jsonLatex: String,
        measurementToken: String
    ) -> String {
        """
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
            width: 100%;
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
        #math { display: inline-block; max-width: min(100%, \(clampedMaxWidth)px); overflow-x: auto; }
        </style>
        </head>
        <body>
        <div id="math"></div>
        <script>
        document.addEventListener('DOMContentLoaded', function() {
            var latexStr = \(jsonLatex);
            var token = "\(measurementToken)";
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
            function reportHeight() {
                var node = document.getElementById('math');
                var h = node ? Math.ceil(node.getBoundingClientRect().height) : 0;
                if (h > 0) {
                    window.webkit.messageHandlers.sizeCallback.postMessage({ token: token, height: h });
                }
            }
            reportHeight();
            setTimeout(reportHeight, 100);
            setTimeout(reportHeight, 300);
            setTimeout(reportHeight, 600);
            if (typeof ResizeObserver !== 'undefined') {
                var ro = new ResizeObserver(function() { reportHeight(); });
                ro.observe(document.getElementById('math'));
            }
        });
        </script>
        </body>
        </html>
        """
    }
}
