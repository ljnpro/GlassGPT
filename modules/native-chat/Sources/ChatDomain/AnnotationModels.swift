import Foundation

/// A citation referencing a URL source within assistant-generated text.
public struct URLCitation: PayloadCodable, Identifiable, Equatable {
    /// A composite identifier derived from the character range and URL.
    public var id: String {
        "\(startIndex)-\(endIndex)-\(url)"
    }

    /// The source URL being cited.
    public var url: String
    /// The title of the cited source.
    public var title: String
    /// The character offset where the cited span begins in the response text.
    public var startIndex: Int
    /// The character offset where the cited span ends in the response text.
    public var endIndex: Int

    /// Creates a new URL citation.
    /// - Parameters:
    ///   - url: The source URL.
    ///   - title: The title of the cited source.
    ///   - startIndex: The start character offset of the cited span.
    ///   - endIndex: The end character offset of the cited span.
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
}

/// An annotation referencing a file path generated in a sandbox environment.
public struct FilePathAnnotation: PayloadCodable, Identifiable, Equatable {
    /// A composite identifier derived from the character range and file ID.
    public var id: String {
        "\(startIndex)-\(endIndex)-\(fileId)"
    }

    /// The API-assigned file identifier.
    public var fileId: String
    /// The optional container (sandbox) identifier that owns this file.
    public var containerId: String?
    /// The file path within the sandbox environment.
    public var sandboxPath: String
    /// The human-readable filename, if available.
    public var filename: String?
    /// The character offset where the annotated span begins in the response text.
    public var startIndex: Int
    /// The character offset where the annotated span ends in the response text.
    public var endIndex: Int

    /// Creates a new file path annotation.
    /// - Parameters:
    ///   - fileId: The API-assigned file identifier.
    ///   - containerId: The optional container identifier.
    ///   - sandboxPath: The file path within the sandbox.
    ///   - filename: The human-readable filename.
    ///   - startIndex: The start character offset of the annotated span.
    ///   - endIndex: The end character offset of the annotated span.
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
}
