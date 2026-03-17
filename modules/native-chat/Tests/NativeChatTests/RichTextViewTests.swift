import XCTest
@testable import NativeChat

@MainActor
final class RichTextViewTests: XCTestCase {
    func testFindFilePathAnnotationPrefersExactSandboxMatch() {
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

        XCTAssertEqual(
            view.findFilePathAnnotation(for: "sandbox:/mnt/data/chart.png"),
            exact
        )
    }

    func testFindFilePathAnnotationFallsBackToFilenameMatch() {
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

        XCTAssertEqual(
            view.findFilePathAnnotation(for: "sandbox:/mnt/data/report.csv"),
            report
        )
    }

    func testFindFilePathAnnotationReturnsOnlyAnnotationAsLastResort() {
        let only = makeAnnotation(
            fileId: "file-only",
            sandboxPath: "/private/var/mobile/output.json",
            filename: "output.json"
        )
        let view = RichTextView(segments: [], filePathAnnotations: [only])

        XCTAssertEqual(
            view.findFilePathAnnotation(for: "sandbox:/mnt/data/unrelated-name.txt"),
            only
        )
    }

    func testFindFilePathAnnotationReturnsNilWhenNoUniqueMatchExists() {
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

        XCTAssertNil(view.findFilePathAnnotation(for: "sandbox:/mnt/data/unknown.txt"))
    }

    func testLatexToUnicodeConvertsRepresentativeMathCommands() {
        let view = RichTextView(segments: [])

        XCTAssertEqual(
            view.latexToUnicode(#"\frac{\alpha_2^n}{x} + \text{speed} + \vec{v} \rightarrow \infty"#),
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
