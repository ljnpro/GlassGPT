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

    static func findResourceDirectory() -> URL? {
        for bundle in candidateBundles {
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

        return nil
    }

    static func findResource(named name: String, ext: String) -> URL? {
        for bundle in candidateBundles {
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

        return nil
    }
}
