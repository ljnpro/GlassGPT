import Foundation

extension KaTeXProvider {
    static var candidateBundles: [Bundle] {
        var bundles: [Bundle] = []
        #if SWIFT_PACKAGE
        bundles.append(.module)
        #endif
        bundles.append(contentsOf: Bundle.allBundles)
        bundles.append(Bundle.main)
        return bundles
    }

    static func findResourceDirectory() -> URL? {
        for bundle in candidateBundles {
            if let cssURL = bundle.url(forResource: "katex.min", withExtension: "css") {
                return cssURL.deletingLastPathComponent()
            }

            if let resourcePath = bundle.resourcePath {
                let resourcesDir = URL(fileURLWithPath: resourcePath).appendingPathComponent("Resources")
                let cssPath = resourcesDir.appendingPathComponent("katex.min.css")
                if FileManager.default.fileExists(atPath: cssPath.path) {
                    return resourcesDir
                }
            }
        }

        if let podBundle = Bundle(identifier: "org.cocoapods.NativeChat"),
           let cssURL = podBundle.url(forResource: "katex.min", withExtension: "css") {
            return cssURL.deletingLastPathComponent()
        }

        return nil
    }

    static func findResource(named name: String, ext: String) -> URL? {
        for bundle in Bundle.allBundles + [Bundle.main] {
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
