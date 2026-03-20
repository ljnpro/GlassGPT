import Foundation
import Testing
@testable import OpenAITransport

struct OpenAIMultipartFormBodyTests {
    @Test func `multipart filename header is truncated to 255 bytes`() {
        let filename = String(repeating: "a", count: 300) + ".txt"
        let body = OpenAIMultipartFormBody(
            boundary: "Boundary-UnitTest",
            purpose: "user_data",
            filename: filename,
            mimeType: "text/plain",
            fileData: Data()
        )
        let bodyString = String(decoding: body.data, as: UTF8.self)

        guard let filenameStart = bodyString.range(of: "filename=\"")?.upperBound,
              let filenameEnd = bodyString[filenameStart...].range(of: "\"\r\n")?.lowerBound
        else {
            Issue.record("Expected multipart file disposition header")
            return
        }

        let headerFilename = String(bodyString[filenameStart ..< filenameEnd])
        #expect(headerFilename.utf8.count == 255)
    }
}
