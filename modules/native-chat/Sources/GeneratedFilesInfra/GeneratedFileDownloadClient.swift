import Foundation
import OpenAITransport

struct GeneratedFileDownloadClient {
    let configurationProvider: OpenAIConfigurationProvider
    let requestAuthorizer: OpenAIRequestAuthorizer
    let transport: OpenAIDataTransport
    let namingResolver: GeneratedFileNamingResolver

    init(
        configurationProvider: OpenAIConfigurationProvider,
        requestAuthorizer: OpenAIRequestAuthorizer,
        transport: OpenAIDataTransport,
        namingResolver: GeneratedFileNamingResolver = GeneratedFileNamingResolver()
    ) {
        self.configurationProvider = configurationProvider
        self.requestAuthorizer = requestAuthorizer
        self.transport = transport
        self.namingResolver = namingResolver
    }

    func downloadValidatedGeneratedFile(
        fileId: String,
        containerId: String?,
        suggestedFilename: String?,
        apiKey: String
    ) async throws -> FileDownloadService.GeneratedFilePayload {
        var lastError: Error = FileDownloadError.invalidGeneratedFileData
        let attemptDirectFlags: [Bool] = configurationProvider.resolvedRoute.usesDirectBaseURL ? [true] : [false, true]

        for useDirectBaseURL in attemptDirectFlags {
            do {
                let (data, response) = try await downloadFromAPI(
                    fileId: fileId,
                    containerId: containerId,
                    apiKey: apiKey,
                    useDirectBaseURL: useDirectBaseURL
                )

                let filename = namingResolver.resolveFilename(
                    suggestedFilename: suggestedFilename,
                    fileId: fileId,
                    response: response,
                    data: data
                )
                let openBehavior = GeneratedFileCachePolicy.openBehavior(for: filename)
                let cacheBucket = GeneratedFileCachePolicy.cacheBucket(for: filename)

                switch openBehavior {
                case .imagePreview:
                    guard GeneratedFileCachePolicy.isGeneratedImageFilename(filename),
                          GeneratedFileCachePolicy.isRenderableImageData(data)
                    else {
                        lastError = FileDownloadError.invalidImageData
                        continue
                    }
                case .pdfPreview:
                    guard GeneratedFileCachePolicy.isGeneratedPDFFilename(filename),
                          GeneratedFileCachePolicy.isRenderablePDFData(data)
                    else {
                        lastError = FileDownloadError.invalidPDFData
                        continue
                    }
                case .directShare:
                    break
                }

                return FileDownloadService.GeneratedFilePayload(
                    data: data,
                    filename: filename,
                    cacheBucket: cacheBucket,
                    openBehavior: openBehavior
                )
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    func downloadFromAPI(
        fileId: String,
        containerId: String?,
        apiKey: String,
        useDirectBaseURL: Bool = false
    ) async throws -> (Data, URLResponse) {
        let endpoint = configurationProvider.resolvedEndpoint(useDirectBaseURL: useDirectBaseURL)
        let urlString = if let containerId, !containerId.isEmpty {
            "\(endpoint.baseURL)/containers/\(containerId)/files/\(fileId)/content"
        } else {
            "\(endpoint.baseURL)/files/\(fileId)/content"
        }

        guard let url = URL(string: urlString) else {
            throw FileDownloadError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 120
        requestAuthorizer.applyAuthorization(
            to: &request,
            apiKey: apiKey,
            includeCloudflareAuthorization: endpoint.includeCloudflareAuthorization
        )

        let (data, response) = try await transport.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FileDownloadError.invalidResponse
        }

        if httpResponse.statusCode >= 400 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Download failed"
            throw FileDownloadError.httpError(httpResponse.statusCode, errorMsg)
        }

        return (data, response)
    }
}
