import ChatDomain
import CryptoKit
import Foundation

/// Encodes, decodes, and applies structured message payloads (citations, tool calls,
/// file attachments, and file-path annotations) stored as binary blobs on ``Message``.
public enum MessagePayloadStore {
    /// Decodes URL citations from binary data.
    public static func annotations(from data: Data?) -> [URLCitation] {
        URLCitation.decode(data) ?? []
    }

    /// Decodes tool call metadata from binary data.
    public static func toolCalls(from data: Data?) -> [ToolCallInfo] {
        ToolCallInfo.decode(data) ?? []
    }

    /// Decodes file attachments from binary data.
    public static func fileAttachments(from data: Data?) -> [FileAttachment] {
        FileAttachment.decode(data) ?? []
    }

    /// Decodes file-path annotations from binary data.
    public static func filePathAnnotations(from data: Data?) -> [FilePathAnnotation] {
        FilePathAnnotation.decode(data) ?? []
    }

    /// Encodes URL citations to binary data, returning `nil` for empty or nil input.
    public static func encodeAnnotations(_ items: [URLCitation]?) -> Data? {
        URLCitation.encode(items)
    }

    /// Encodes tool call metadata to binary data.
    public static func encodeToolCalls(_ items: [ToolCallInfo]?) -> Data? {
        ToolCallInfo.encode(items)
    }

    /// Encodes file attachments to binary data.
    public static func encodeFileAttachments(_ items: [FileAttachment]?) -> Data? {
        FileAttachment.encode(items)
    }

    /// Encodes file-path annotations to binary data.
    public static func encodeFilePathAnnotations(_ items: [FilePathAnnotation]?) -> Data? {
        FilePathAnnotation.encode(items)
    }

    /// Writes URL citations to the given message's `annotationsData` blob.
    public static func setAnnotations(_ items: [URLCitation], on message: Message) {
        message.annotationsData = encodeAnnotations(items.isEmpty ? nil : items)
    }

    /// Writes tool call metadata to the given message's `toolCallsData` blob.
    public static func setToolCalls(_ items: [ToolCallInfo], on message: Message) {
        message.toolCallsData = encodeToolCalls(items.isEmpty ? nil : items)
    }

    /// Writes file attachments to the given message's `fileAttachmentsData` blob.
    public static func setFileAttachments(_ items: [FileAttachment], on message: Message) {
        message.fileAttachmentsData = encodeFileAttachments(items.isEmpty ? nil : items)
    }

    /// Writes file-path annotations to the given message's `filePathAnnotationsData` blob.
    public static func setFilePathAnnotations(_ items: [FilePathAnnotation], on message: Message) {
        message.filePathAnnotationsData = encodeFilePathAnnotations(items.isEmpty ? nil : items)
    }

    /// Computes a SHA-256 hex digest of all payload fields on the given message.
    public static func renderDigest(for message: Message) -> String {
        renderDigest(
            annotations: annotations(from: message.annotationsData),
            toolCalls: toolCalls(from: message.toolCallsData),
            fileAttachments: fileAttachments(from: message.fileAttachmentsData),
            filePathAnnotations: filePathAnnotations(from: message.filePathAnnotationsData)
        )
    }

    /// Computes a SHA-256 hex digest from individual payload arrays.
    public static func renderDigest(
        annotations: [URLCitation],
        toolCalls: [ToolCallInfo],
        fileAttachments: [FileAttachment],
        filePathAnnotations: [FilePathAnnotation]
    ) -> String {
        let digest = SHA256()
            .updating(with: canonicalData(for: annotations))
            .updating(with: canonicalData(for: toolCalls))
            .updating(with: canonicalData(for: fileAttachments))
            .updating(with: canonicalData(for: filePathAnnotations))
            .finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalData<T: Encodable>(for value: T) -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(value)
        } catch {
            return Data()
        }
    }
}

private extension SHA256 {
    func updating(with data: Data) -> SHA256 {
        var copy = self
        copy.update(data: data)
        return copy
    }
}
