import ChatDomain
import GeneratedFilesCore
import Testing

@Suite(.tags(.parsing, .persistence))
struct GeneratedFilesPolicyTests {
    @Test func `generated file policy resolves cache and open behavior`() {
        let imageDescriptor = GeneratedFileDescriptor(
            fileID: "file_image",
            containerID: "container_1",
            filename: "chart.png",
            mediaType: "image/png"
        )
        let pdfDescriptor = GeneratedFileDescriptor(
            fileID: "file_pdf",
            filename: "report.pdf",
            mediaType: "application/pdf"
        )
        let textDescriptor = GeneratedFileDescriptor(
            fileID: "file_txt",
            filename: "notes.txt",
            mediaType: "text/plain"
        )

        #expect(GeneratedFilePolicy.cacheBucket(for: imageDescriptor) == .image)
        #expect(GeneratedFilePolicy.cacheBucket(for: pdfDescriptor) == .document)
        #expect(GeneratedFilePolicy.openBehavior(for: imageDescriptor) == .imagePreview)
        #expect(GeneratedFilePolicy.openBehavior(for: pdfDescriptor) == .pdfPreview)
        #expect(GeneratedFilePolicy.openBehavior(for: textDescriptor) == .directShare)
        #expect(
            GeneratedFilePolicy.cacheKey(for: imageDescriptor)
                == GeneratedFileCacheKey(identity: "container_1:file_image", bucket: .image)
        )
    }

    @Test func `generated file policy resolves filenames from descriptor metadata and fallback`() {
        let unnamedDescriptor = GeneratedFileDescriptor(fileID: "file_123", filename: nil, mediaType: nil)
        let metadata = GeneratedFileResponseMetadata(
            suggestedFilename: "/tmp/export",
            contentDispositionFilename: "team-plan"
        )

        #expect(
            GeneratedFilePolicy.resolvedFilename(
                for: GeneratedFileDescriptor(fileID: "f1", filename: "invoice.pdf", mediaType: nil),
                responseMetadata: metadata,
                inferredExtension: "pdf"
            ) == "invoice.pdf"
        )
        #expect(
            GeneratedFilePolicy.resolvedFilename(
                for: unnamedDescriptor,
                responseMetadata: metadata,
                inferredExtension: "pdf"
            ) == "team-plan.pdf"
        )
        #expect(
            GeneratedFilePolicy.resolvedFilename(
                for: unnamedDescriptor,
                responseMetadata: .init(),
                inferredExtension: ".csv"
            ) == "file_123.csv"
        )
    }

    @Test func `generated file policy normalizes filenames and extensions`() {
        #expect(GeneratedFilePolicy.normalizedFilename(nil) == nil)
        #expect(GeneratedFilePolicy.normalizedFilename("   ") == nil)
        #expect(GeneratedFilePolicy.normalizedFilename("/tmp/demo.txt") == "demo.txt")
        #expect(
            GeneratedFilePolicy.normalizedFilename("summary", inferredExtension: "PDF") == "summary.pdf"
        )
        #expect(
            GeneratedFilePolicy.normalizedFilename("already.png", inferredExtension: "jpg") == "already.png"
        )
    }

    @Test func `annotation matcher resolves direct download and filename fallbacks`() {
        let matcher = GeneratedFileAnnotationMatcher()
        let annotation = FilePathAnnotation(
            fileId: "file_1",
            containerId: nil,
            sandboxPath: "/sandbox/reports/output.csv",
            filename: nil,
            startIndex: 0,
            endIndex: 3
        )
        let legacyAnnotation = FilePathAnnotation(
            fileId: "cfile_legacy",
            containerId: nil,
            sandboxPath: "/sandbox/reports/legacy.csv",
            filename: "legacy.csv",
            startIndex: 0,
            endIndex: 3
        )
        let containerAnnotation = FilePathAnnotation(
            fileId: "cfile_legacy",
            containerId: "container_1",
            sandboxPath: "/sandbox/reports/container.csv",
            filename: "container.csv",
            startIndex: 0,
            endIndex: 3
        )

        #expect(matcher.requestedFilename(for: "sandbox:/sandbox/reports/output.csv", annotation: annotation) == "output.csv")
        #expect(matcher.requestedFilename(for: "sandbox:/sandbox/reports/legacy.csv", annotation: legacyAnnotation) == "legacy.csv")
        #expect(matcher.annotationCanDownloadDirectly(annotation))
        #expect(!matcher.annotationCanDownloadDirectly(legacyAnnotation))
        #expect(matcher.annotationCanDownloadDirectly(containerAnnotation))
    }

    @Test func `annotation matcher finds best matching annotation across strategies`() {
        let matcher = GeneratedFileAnnotationMatcher()
        let exactFile = FilePathAnnotation(
            fileId: "file_exact",
            containerId: nil,
            sandboxPath: "/tmp/exact.txt",
            filename: "exact.txt",
            startIndex: 0,
            endIndex: 1
        )
        let pathMatch = FilePathAnnotation(
            fileId: "file_path",
            containerId: nil,
            sandboxPath: "/tmp/nested/path/data.json",
            filename: nil,
            startIndex: 0,
            endIndex: 1
        )
        let filenameMatch = FilePathAnnotation(
            fileId: "file_name",
            containerId: nil,
            sandboxPath: "/another/place/final.csv",
            filename: "final.csv",
            startIndex: 0,
            endIndex: 1
        )

        #expect(
            matcher.findMatchingFilePathAnnotation(
                in: [exactFile, pathMatch],
                sandboxURL: "sandbox:/elsewhere/ignored.txt",
                fallback: exactFile
            )?.fileId == "file_exact"
        )
        #expect(
            matcher.findMatchingFilePathAnnotation(
                in: [pathMatch],
                sandboxURL: "sandbox:/tmp/nested/path/data.json",
                fallback: nil
            )?.fileId == "file_path"
        )
        #expect(
            matcher.findMatchingFilePathAnnotation(
                in: [pathMatch],
                sandboxURL: "sandbox:/var/mobile/tmp/nested/path/data.json",
                fallback: nil
            )?.fileId == "file_path"
        )
        #expect(
            matcher.findMatchingFilePathAnnotation(
                in: [filenameMatch],
                sandboxURL: "sandbox:/random/final.csv",
                fallback: nil
            )?.fileId == "file_name"
        )
        #expect(
            matcher.findMatchingFilePathAnnotation(
                in: [filenameMatch, pathMatch],
                sandboxURL: "sandbox:/unmatched/none.bin",
                fallback: filenameMatch
            )?.fileId == "file_name"
        )
    }
}
