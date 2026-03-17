import Foundation

struct URLCitation: Codable, Sendable, Identifiable, Equatable {
    var id: String { "\(startIndex)-\(endIndex)-\(url)" }
    var url: String
    var title: String
    var startIndex: Int
    var endIndex: Int

    static func encode(_ items: [URLCitation]?) -> Data? {
        guard let items = items, !items.isEmpty else { return nil }
        do {
            return try JSONCoding.encode(items)
        } catch {
            Loggers.persistence.error("[URLCitation.encode] \(error.localizedDescription)")
            return nil
        }
    }

    static func decode(_ data: Data?) -> [URLCitation]? {
        guard let data else { return nil }
        do {
            return try JSONCoding.decode([URLCitation].self, from: data)
        } catch {
            Loggers.persistence.error("[URLCitation.decode] \(error.localizedDescription)")
            return nil
        }
    }
}

struct FilePathAnnotation: Codable, Sendable, Identifiable, Equatable {
    var id: String { "\(startIndex)-\(endIndex)-\(fileId)" }
    var fileId: String
    var containerId: String?
    var sandboxPath: String
    var filename: String?
    var startIndex: Int
    var endIndex: Int

    static func encode(_ items: [FilePathAnnotation]?) -> Data? {
        guard let items = items, !items.isEmpty else { return nil }
        do {
            return try JSONCoding.encode(items)
        } catch {
            Loggers.persistence.error("[FilePathAnnotation.encode] \(error.localizedDescription)")
            return nil
        }
    }

    static func decode(_ data: Data?) -> [FilePathAnnotation]? {
        guard let data else { return nil }
        do {
            return try JSONCoding.decode([FilePathAnnotation].self, from: data)
        } catch {
            Loggers.persistence.error("[FilePathAnnotation.decode] \(error.localizedDescription)")
            return nil
        }
    }
}
