import Foundation
import Testing
@testable import ChatUIComponents

@MainActor
struct KaTeXProviderTests {
    @Test func `load content reads utf8 resource data`() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("katex-test.css")
        try "body{}".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let content = KaTeXProvider.loadContent(from: fileURL)

        #expect(content == "body{}")
    }

    @Test func `load content reports failure for unreadable resource`() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.js")
        var failureMessage: String?

        let content = KaTeXProvider.loadContent(
            from: missingURL,
            onFailure: { message in
                failureMessage = message
            },
            logFailure: false
        )

        #expect(content == nil)
        #expect(failureMessage?.contains("Failed to load KaTeX resource") == true)
    }

    @Test func `find resource directory reports failure when bundles do not contain katex assets`() {
        var failureMessage: String?

        let resourceDirectory = KaTeXProvider.findResourceDirectory(
            in: [Bundle(for: BundleProbe.self)],
            onFailure: { message in
                failureMessage = message
            },
            logFailure: false
        )

        #expect(resourceDirectory == nil)
        #expect(failureMessage == "Failed to locate KaTeX resource directory in loaded bundles.")
    }

    @Test func `find resource reports failure when bundles do not contain requested asset`() {
        var failureMessage: String?

        let resourceURL = KaTeXProvider.findResource(
            named: "katex.min",
            ext: "css",
            in: [Bundle(for: BundleProbe.self)],
            onFailure: { message in
                failureMessage = message
            },
            logFailure: false
        )

        #expect(resourceURL == nil)
        #expect(failureMessage == "Failed to locate KaTeX resource katex.min.css in loaded bundles.")
    }
}

private final class BundleProbe {}
