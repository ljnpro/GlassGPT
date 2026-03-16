import SwiftUI
import SwiftData

// MARK: - Model Type

enum ModelType: String, CaseIterable, Identifiable, Codable, Sendable {
    case gpt5_4 = "gpt-5.4"
    case gpt5_4_pro = "gpt-5.4-pro"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt5_4: return "GPT-5.4"
        case .gpt5_4_pro: return "GPT-5.4 Pro"
        }
    }

    /// Available reasoning effort levels for this model
    var availableEfforts: [ReasoningEffort] {
        switch self {
        case .gpt5_4:
            return [.none, .low, .medium, .high, .xhigh]
        case .gpt5_4_pro:
            return [.medium, .high, .xhigh]
        }
    }

    /// Default reasoning effort for this model
    var defaultEffort: ReasoningEffort {
        switch self {
        case .gpt5_4: return .high
        case .gpt5_4_pro: return .xhigh
        }
    }
}

// MARK: - Reasoning Effort

enum ReasoningEffort: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case low
    case medium
    case high
    case xhigh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "XHigh"
        }
    }

    /// The value sent to the API (xhigh maps to the API string)
    var apiValue: String {
        rawValue
    }
}

// MARK: - Service Tier

enum ServiceTier: String, CaseIterable, Identifiable, Codable, Sendable {
    case standard = "default"
    case flex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .flex: return "Flex"
        }
    }
}

// MARK: - App Theme

enum AppTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Message Role

enum MessageRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case user
    case assistant
    case system

    var id: String { rawValue }
}

// MARK: - Tool Call Types

enum ToolCallType: String, Codable, Sendable, Equatable {
    case webSearch = "web_search"
    case codeInterpreter = "code_interpreter"
    case fileSearch = "file_search"
}

enum ToolCallStatus: String, Codable, Sendable, Equatable {
    case inProgress = "in_progress"
    case searching
    case interpreting
    case fileSearching = "file_searching"
    case completed
}

/// Represents a tool call made by the model during response generation.
struct ToolCallInfo: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var type: ToolCallType
    var status: ToolCallStatus
    var code: String?           // For code interpreter: the Python code
    var results: [String]?      // For code interpreter: execution results
    var queries: [String]?      // For web search: search queries used

    /// Encode an array of ToolCallInfo to Data for SwiftData storage.
    static func encode(_ items: [ToolCallInfo]?) -> Data? {
        guard let items = items, !items.isEmpty else { return nil }
        return try? JSONEncoder().encode(items)
    }

    /// Decode an array of ToolCallInfo from Data.
    static func decode(_ data: Data?) -> [ToolCallInfo]? {
        guard let data = data else { return nil }
        return try? JSONDecoder().decode([ToolCallInfo].self, from: data)
    }
}

// MARK: - URL Citation

/// A citation from web search results, linking to a source URL.
struct URLCitation: Codable, Sendable, Identifiable, Equatable {
    var id: String { "\(startIndex)-\(endIndex)-\(url)" }
    var url: String
    var title: String
    var startIndex: Int
    var endIndex: Int

    /// Encode an array of URLCitation to Data for SwiftData storage.
    static func encode(_ items: [URLCitation]?) -> Data? {
        guard let items = items, !items.isEmpty else { return nil }
        return try? JSONEncoder().encode(items)
    }

    /// Decode an array of URLCitation from Data.
    static func decode(_ data: Data?) -> [URLCitation]? {
        guard let data = data else { return nil }
        return try? JSONDecoder().decode([URLCitation].self, from: data)
    }
}

// MARK: - File Path Annotation

/// A file path annotation from code interpreter output, linking a sandbox path to a downloadable file_id.
struct FilePathAnnotation: Codable, Sendable, Identifiable, Equatable {
    var id: String { "\(startIndex)-\(endIndex)-\(fileId)" }
    var fileId: String
    var containerId: String?
    var sandboxPath: String
    var filename: String?
    var startIndex: Int
    var endIndex: Int

    /// Encode an array of FilePathAnnotation to Data for SwiftData storage.
    static func encode(_ items: [FilePathAnnotation]?) -> Data? {
        guard let items = items, !items.isEmpty else { return nil }
        return try? JSONEncoder().encode(items)
    }

    /// Decode an array of FilePathAnnotation from Data.
    static func decode(_ data: Data?) -> [FilePathAnnotation]? {
        guard let data = data else { return nil }
        return try? JSONDecoder().decode([FilePathAnnotation].self, from: data)
    }
}

// MARK: - File Attachment

enum FileUploadStatus: String, Codable, Sendable {
    case pending
    case uploading
    case uploaded
    case failed
}

/// A file attached to a message (user-uploaded document).
struct FileAttachment: Codable, Sendable, Identifiable {
    var id: UUID
    var filename: String
    var fileSize: Int64
    var fileType: String        // pdf, docx, pptx, csv, xlsx
    var fileId: String?         // OpenAI file ID after upload (alias for openAIFileId)
    var uploadStatus: FileUploadStatus

    /// Local file data for upload (not persisted in JSON — transient only).
    /// This is excluded from Codable encoding to avoid bloating SwiftData storage.
    var localData: Data?

    enum CodingKeys: String, CodingKey {
        case id, filename, fileSize, fileType, fileId, uploadStatus
        // localData is intentionally excluded from Codable
    }

    /// Convenience alias: get/set `fileId` via `openAIFileId`.
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

    /// Human-readable file size string
    var fileSizeString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    /// SF Symbol name for this file type
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

    /// Color for the file type icon
    var iconColor: Color {
        switch fileType.lowercased() {
        case "pdf": return .red
        case "docx", "doc": return .blue
        case "pptx", "ppt": return .orange
        case "csv": return .green
        case "xlsx", "xls": return .green
        default: return .secondary
        }
    }

    /// Encode an array of FileAttachment to Data for SwiftData storage.
    static func encode(_ items: [FileAttachment]?) -> Data? {
        guard let items = items, !items.isEmpty else { return nil }
        return try? JSONEncoder().encode(items)
    }

    /// Decode an array of FileAttachment from Data.
    static func decode(_ data: Data?) -> [FileAttachment]? {
        guard let data = data else { return nil }
        return try? JSONDecoder().decode([FileAttachment].self, from: data)
    }
}
