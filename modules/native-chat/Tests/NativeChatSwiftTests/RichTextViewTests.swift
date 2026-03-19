import Foundation
import Testing
import ChatDomain
import NativeChatUI
@testable import NativeChatComposition

@MainActor
struct RichTextViewTests {
    @Test func findFilePathAnnotationPrefersExactSandboxMatch() {
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

    @Test func findFilePathAnnotationFallsBackToFilenameMatch() {
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

    @Test func findFilePathAnnotationReturnsOnlyAnnotationAsLastResort() {
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

    @Test func findFilePathAnnotationReturnsNilWhenNoUniqueMatchExists() {
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

    @Test func latexToUnicodeConvertsRepresentativeMathCommands() {
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
