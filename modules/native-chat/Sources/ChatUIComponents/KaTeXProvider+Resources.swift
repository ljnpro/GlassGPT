import Foundation

extension KaTeXProvider {
    static var candidateBundles: [Bundle] {
        var bundles: [Bundle] = []
        #if SWIFT_PACKAGE
        bundles.append(.module)
        #endif
        bundles.append(contentsOf: Bundle.allBundles)
        return bundles
    }

    static func findResourceDirectory(
        in bundles: [Bundle] = candidateBundles,
        onFailure: ((String) -> Void)? = nil,
        logFailure: Bool = true
    ) -> URL? {
        for bundle in bundles {
            if let cssURL = bundle.url(forResource: "katex.min", withExtension: "css") {
                return cssURL.deletingLastPathComponent()
            }

            if let resourcePath = bundle.resourcePath {
                let resourcesDirectory = URL(fileURLWithPath: resourcePath).appendingPathComponent("Resources")
                let cssPath = resourcesDirectory.appendingPathComponent("katex.min.css")
                if FileManager.default.fileExists(atPath: cssPath.path) {
                    return resourcesDirectory
                }
            }
        }

        let message = "Failed to locate KaTeX resource directory in loaded bundles."
        onFailure?(message)
        if logFailure {
            Self.logger.error("\(message, privacy: .public)")
        }
        return nil
    }

    static func findResource(
        named name: String,
        ext: String,
        in bundles: [Bundle] = candidateBundles,
        onFailure: ((String) -> Void)? = nil,
        logFailure: Bool = true
    ) -> URL? {
        for bundle in bundles {
            if let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }

            if let resourcePath = bundle.resourcePath {
                let path = URL(fileURLWithPath: resourcePath)
                    .appendingPathComponent("Resources")
                    .appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: path.path) {
                    return path
                }
            }
        }

        let message = "Failed to locate KaTeX resource \(name).\(ext) in loaded bundles."
        onFailure?(message)
        if logFailure {
            Self.logger.error("\(message, privacy: .public)")
        }
        return nil
    }
}
