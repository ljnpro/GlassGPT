import Foundation

public enum FileUploadStatus: String, Codable, Sendable {
    case pending
    case uploading
    case uploaded
    case failed
}

public struct FileAttachment: Codable, Sendable, Identifiable {
    public var id: UUID
    public var filename: String
    public var fileSize: Int64
    public var fileType: String
    public var fileId: String?
    public var uploadStatus: FileUploadStatus
    public var localData: Data?

    enum CodingKeys: String, CodingKey {
        case id, filename, fileSize, fileType, fileId, uploadStatus
    }

    public var openAIFileId: String? {
        get { fileId }
        set { fileId = newValue }
    }

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

    public var fileSizeString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    public var iconName: String {
        switch fileType.lowercased() {
        case "pdf": return "doc.richtext"
        case "docx", "doc": return "doc.text"
        case "pptx", "ppt": return "doc.text.image"
        case "csv": return "tablecells"
        case "xlsx", "xls": return "tablecells.badge.ellipsis"
        default: return "doc"
        }
    }

    public static func encode(_ items: [FileAttachment]?) -> Data? {
        guard let items, !items.isEmpty else { return nil }
        do {
            return try PayloadJSONCoding.encode(items)
        } catch {
            return nil
        }
    }

    public static func decode(_ data: Data?) -> [FileAttachment]? {
        guard let data else { return nil }
        do {
            return try PayloadJSONCoding.decode([FileAttachment].self, from: data)
        } catch {
            return nil
        }
    }
}
