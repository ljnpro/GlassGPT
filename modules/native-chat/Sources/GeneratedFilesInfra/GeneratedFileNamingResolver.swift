import Foundation
import GeneratedFilesCore

struct GeneratedFileNamingResolver {
    func downloadKey(fileId: String, containerId: String?) -> String {
        if let containerId, !containerId.isEmpty {
            return "\(containerId):\(fileId)"
        }
        return fileId
    }

    func resolveFilename(
        suggestedFilename: String?,
        fileId: String,
        response: URLResponse,
        data: Data
    ) -> String {
        let inferredExtension = inferredFileExtension(from: response, data: data)

        if let suggested = normalizedFilename(suggestedFilename, inferredExtension: inferredExtension) {
            return suggested
        }

        if let httpResponse = response as? HTTPURLResponse,
           let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition"),
           let filenameRange = disposition.range(of: "filename=\""),
           let endRange = disposition[filenameRange.upperBound...].range(of: "\"") {
            let extracted = String(disposition[filenameRange.upperBound..<endRange.lowerBound])
            if let normalized = normalizedFilename(extracted, inferredExtension: inferredExtension) {
                return normalized
            }
        }

        if let responseSuggested = response.suggestedFilename,
           !responseSuggested.isEmpty,
           responseSuggested != "Unknown",
           let suggested = normalizedFilename(responseSuggested, inferredExtension: inferredExtension) {
            return suggested
        }

        return "\(fileId).\(inferredExtension ?? "bin")"
    }

    private func normalizedFilename(_ candidate: String?, inferredExtension: String?) -> String? {
        guard let candidate else { return nil }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sanitized = URL(fileURLWithPath: trimmed).lastPathComponent
        guard !sanitized.isEmpty else { return nil }

        if !URL(fileURLWithPath: sanitized).pathExtension.isEmpty {
            return sanitized
        }

        if let inferredExtension, !inferredExtension.isEmpty {
            return "\(sanitized).\(inferredExtension)"
        }

        return sanitized
    }

    private func inferredFileExtension(from response: URLResponse, data: Data) -> String? {
        if let mimeType = response.mimeType,
           let ext = GeneratedFileTypeInspector.extensionForMimeType(mimeType) {
            return ext
        }

        return GeneratedFileTypeInspector.extensionForFileSignature(data)
    }
}
