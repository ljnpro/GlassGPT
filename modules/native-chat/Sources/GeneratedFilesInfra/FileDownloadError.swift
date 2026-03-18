import Foundation

public enum FileDownloadError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(Int, String)
    case fileNotFound
    case invalidImageData
    case invalidPDFData
    case invalidGeneratedFileData

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid file download URL."
        case .invalidResponse: return "Invalid response from server."
        case .httpError(let code, let msg): return "File download error (\(code)): \(msg)"
        case .fileNotFound: return "File not found."
        case .invalidImageData: return "The generated image could not be rendered."
        case .invalidPDFData: return "The generated PDF could not be rendered."
        case .invalidGeneratedFileData: return "The generated file could not be downloaded."
        }
    }
}
