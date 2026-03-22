import Foundation
import Testing
@testable import OpenAITransport

struct OpenAIMultipartFormBodyTests {
    @Test func `multipart filename metadata reports truncation at 255 bytes`() {
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
        #expect(body.didTruncateFilename)
        #expect(headerFilename.utf8.count == 255)
    }

    @Test func `upload request rejects filename that exceeds multipart header limit`() throws {
        let builder = OpenAIRequestBuilder(
            configuration: DefaultOpenAIConfigurationProvider(
                directOpenAIBaseURL: "https://api.openai.com/v1",
                cloudflareGatewayBaseURL: DefaultOpenAIConfigurationProvider.defaultCloudflareGatewayBaseURL,
                cloudflareAIGToken: "",
                useCloudflareGateway: false
            )
        )
        let filename = String(repeating: "a", count: 300) + ".txt"

        #expect(throws: OpenAIServiceError.self) {
            _ = try builder.uploadRequest(
                data: Data(),
                filename: filename,
                apiKey: "sk-test"
            )
        }
    }
}
