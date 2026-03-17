import Foundation

public struct URLCitation: Codable, Sendable, Identifiable, Equatable {
    public var id: String { "\(startIndex)-\(endIndex)-\(url)" }
    public var url: String
    public var title: String
    public var startIndex: Int
    public var endIndex: Int

    public init(
        url: String,
        title: String,
        startIndex: Int,
        endIndex: Int
    ) {
        self.url = url
        self.title = title
        self.startIndex = startIndex
        self.endIndex = endIndex
    }

    public static func encode(_ items: [URLCitation]?) -> Data? {
        guard let items, !items.isEmpty else { return nil }
        do {
            return try PayloadJSONCoding.encode(items)
        } catch {
            return nil
        }
    }

    public static func decode(_ data: Data?) -> [URLCitation]? {
        guard let data else { return nil }
        do {
            return try PayloadJSONCoding.decode([URLCitation].self, from: data)
        } catch {
            return nil
        }
    }
}

public struct FilePathAnnotation: Codable, Sendable, Identifiable, Equatable {
    public var id: String { "\(startIndex)-\(endIndex)-\(fileId)" }
    public var fileId: String
    public var containerId: String?
    public var sandboxPath: String
    public var filename: String?
    public var startIndex: Int
    public var endIndex: Int

    public init(
        fileId: String,
        containerId: String?,
        sandboxPath: String,
        filename: String?,
        startIndex: Int,
        endIndex: Int
    ) {
        self.fileId = fileId
        self.containerId = containerId
        self.sandboxPath = sandboxPath
        self.filename = filename
        self.startIndex = startIndex
        self.endIndex = endIndex
    }

    public static func encode(_ items: [FilePathAnnotation]?) -> Data? {
        guard let items, !items.isEmpty else { return nil }
        do {
            return try PayloadJSONCoding.encode(items)
        } catch {
            return nil
        }
    }

    public static func decode(_ data: Data?) -> [FilePathAnnotation]? {
        guard let data else { return nil }
        do {
            return try PayloadJSONCoding.decode([FilePathAnnotation].self, from: data)
        } catch {
            return nil
        }
    }
}
