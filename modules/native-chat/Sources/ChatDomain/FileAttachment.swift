import Foundation

/// The upload lifecycle state of a file attachment.
public enum FileUploadStatus: String, Codable, Sendable, Equatable {
    /// The file has not yet begun uploading.
    case pending
    /// The file is currently being uploaded.
    case uploading
    /// The file has been successfully uploaded.
    case uploaded
    /// The file upload failed.
    case failed
}

/// A file attached to a chat message for upload to the API.
public struct FileAttachment: PayloadCodable, Identifiable, Equatable {
    /// The local unique identifier for this attachment.
    public var id: UUID
    /// The display name of the file.
    public var filename: String
    /// The size of the file in bytes.
    public var fileSize: Int64
    /// The file type extension (e.g. "pdf", "csv").
    public var fileType: String
    /// The API-assigned file identifier after upload, if available.
    public var fileId: String?
    /// The current upload status of this attachment.
    public var uploadStatus: FileUploadStatus
    /// The raw file data for local access, excluded from codable serialization.
    public var localData: Data?

    enum CodingKeys: String, CodingKey {
        case id, filename, fileSize, fileType, fileId, uploadStatus, localData
    }

    /// Alias for ``fileId`` providing semantic clarity when used with OpenAI APIs.
    public var openAIFileId: String? {
        get { fileId }
        set { fileId = newValue }
    }

    /// Creates a new file attachment.
    /// - Parameters:
    ///   - id: A unique identifier. Defaults to a new UUID.
    ///   - filename: The display name of the file.
    ///   - fileSize: The size in bytes. Defaults to 0.
    ///   - fileType: The file type extension.
    ///   - fileId: The API-assigned file identifier.
    ///   - localData: The raw file data for local access.
    ///   - uploadStatus: The initial upload status. Defaults to `.pending`.
    public init(
        id: UUID = UUID(),
        filename: String,
        fileSize: Int64 = 0,
        fileType: String,
        fileId: String? = nil,
        localData: Data? = nil,
        uploadStatus: FileUploadStatus = .pending
    ) {
        self.id = id
        self.filename = filename
        self.fileSize = fileSize
        self.fileType = fileType
        self.fileId = fileId
        self.localData = localData
        self.uploadStatus = uploadStatus
    }

    /// A human-readable string representing the file size (e.g. "1.2 MB").
    public var fileSizeString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    /// The SF Symbol name appropriate for this file's type.
    public var iconName: String {
        switch fileType.lowercased() {
        case "pdf": "doc.richtext"
        case "docx", "doc": "doc.text"
        case "pptx", "ppt": "doc.text.image"
        case "csv": "tablecells"
        case "xlsx", "xls": "tablecells.badge.ellipsis"
        default: "doc"
        }
    }
}
