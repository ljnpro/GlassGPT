import Foundation

enum FileUploadStatus: String, Codable, Sendable {
    case pending
    case uploading
    case uploaded
    case failed
}

struct FileAttachment: Codable, Sendable, Identifiable {
    var id: UUID
    var filename: String
    var fileSize: Int64
    var fileType: String
    var fileId: String?
    var uploadStatus: FileUploadStatus
    var localData: Data?

    enum CodingKeys: String, CodingKey {
        case id, filename, fileSize, fileType, fileId, uploadStatus
    }

    var openAIFileId: String? {
        get { fileId }
        set { fileId = newValue }
    }

    init(
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

    var fileSizeString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var iconName: String {
        switch fileType.lowercased() {
        case "pdf": return "doc.richtext"
        case "docx", "doc": return "doc.text"
        case "pptx", "ppt": return "doc.text.image"
        case "csv": return "tablecells"
        case "xlsx", "xls": return "tablecells.badge.ellipsis"
        default: return "doc"
        }
    }

    static func encode(_ items: [FileAttachment]?) -> Data? {
        guard let items = items, !items.isEmpty else { return nil }
        do {
            return try JSONCoding.encode(items)
        } catch {
            Loggers.persistence.error("[FileAttachment.encode] \(error.localizedDescription)")
            return nil
        }
    }

    static func decode(_ data: Data?) -> [FileAttachment]? {
        guard let data else { return nil }
        do {
            return try JSONCoding.decode([FileAttachment].self, from: data)
        } catch {
            Loggers.persistence.error("[FileAttachment.decode] \(error.localizedDescription)")
            return nil
        }
    }
}
