import Foundation

/// Errors that can occur when downloading a generated file from the OpenAI API.
public enum FileDownloadError: Error, LocalizedError, Sendable {
    /// The constructed download URL was malformed.
    case invalidURL
    /// The server response could not be interpreted as an HTTP response.
    case invalidResponse
    /// The server returned an HTTP error with the given status code and message.
    case httpError(Int, String)
    /// The requested file was not found on the server.
    case fileNotFound
    /// The downloaded data could not be rendered as an image.
    case invalidImageData
    /// The downloaded data could not be rendered as a PDF.
    case invalidPDFData
    /// The downloaded data could not be validated as a usable generated file.
    case invalidGeneratedFileData

    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid file download URL."
        case .invalidResponse: "Invalid response from server."
        case let .httpError(code, msg): "File download error (\(code)): \(msg)"
        case .fileNotFound: "File not found."
        case .invalidImageData: "The generated image could not be rendered."
        case .invalidPDFData: "The generated PDF could not be rendered."
        case .invalidGeneratedFileData: "The generated file could not be downloaded."
        }
    }
}
