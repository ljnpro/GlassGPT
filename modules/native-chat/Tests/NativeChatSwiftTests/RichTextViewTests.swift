import ChatDomain
import Foundation
import NativeChatUI
import Testing
@testable import NativeChatComposition

@MainActor
struct RichTextViewTests {
    @Test func `find file path annotation prefers exact sandbox match`() {
        let exact = makeAnnotation(
            fileId: "file-exact",
            sandboxPath: "sandbox:/mnt/data/chart.png",
            filename: "chart.png"
        )
        let filenameOnly = makeAnnotation(
            fileId: "file-fallback",
            sandboxPath: "/tmp/chart.png",
            filename: "chart.png"
        )
        let view = RichTextView(segments: [], filePathAnnotations: [filenameOnly, exact])

        #expect(
            view.findFilePathAnnotation(for: "sandbox:/mnt/data/chart.png") ==
                exact
        )
    }

    @Test func `find file path annotation falls back to filename match`() {
        let report = makeAnnotation(
            fileId: "file-report",
            sandboxPath: "/private/var/mobile/report.csv",
            filename: "report.csv"
        )
        let other = makeAnnotation(
            fileId: "file-other",
            sandboxPath: "/private/var/mobile/other.csv",
            filename: "other.csv"
        )
        let view = RichTextView(segments: [], filePathAnnotations: [other, report])

        #expect(
            view.findFilePathAnnotation(for: "sandbox:/mnt/data/report.csv") ==
                report
        )
    }

    @Test func `find file path annotation returns only annotation as last resort`() {
        let only = makeAnnotation(
            fileId: "file-only",
            sandboxPath: "/private/var/mobile/output.json",
            filename: "output.json"
        )
        let view = RichTextView(segments: [], filePathAnnotations: [only])

        #expect(
            view.findFilePathAnnotation(for: "sandbox:/mnt/data/unrelated-name.txt") ==
                only
        )
    }

    @Test func `find file path annotation returns nil when no unique match exists`() {
        let first = makeAnnotation(
            fileId: "file-one",
            sandboxPath: "/tmp/one.txt",
            filename: "one.txt"
        )
        let second = makeAnnotation(
            fileId: "file-two",
            sandboxPath: "/tmp/two.txt",
            filename: "two.txt"
        )
        let view = RichTextView(segments: [], filePathAnnotations: [first, second])

        #expect(view.findFilePathAnnotation(for: "sandbox:/mnt/data/unknown.txt") == nil)
    }

    @Test func `latex to unicode converts representative math commands`() {
        let view = RichTextView(segments: [])

        #expect(
            view.latexToUnicode(#"\frac{\alpha_2^n}{x} + \text{speed} + \vec{v} \rightarrow \infty"#) ==
                "α₂ⁿ/x + speed + v⃗ → ∞"
        )
    }

    private func makeAnnotation(
        fileId: String,
        sandboxPath: String,
        filename: String
    ) -> FilePathAnnotation {
        FilePathAnnotation(
            fileId: fileId,
            containerId: nil,
            sandboxPath: sandboxPath,
            filename: filename,
            startIndex: 0,
            endIndex: sandboxPath.count
        )
    }
}
