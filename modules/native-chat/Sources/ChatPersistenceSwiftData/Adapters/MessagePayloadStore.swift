import ChatDomain
import CryptoKit
import Foundation

public enum MessagePayloadStore {
    public static func annotations(from data: Data?) -> [URLCitation] {
        URLCitation.decode(data) ?? []
    }

    public static func toolCalls(from data: Data?) -> [ToolCallInfo] {
        ToolCallInfo.decode(data) ?? []
    }

    public static func fileAttachments(from data: Data?) -> [FileAttachment] {
        FileAttachment.decode(data) ?? []
    }

    public static func filePathAnnotations(from data: Data?) -> [FilePathAnnotation] {
        FilePathAnnotation.decode(data) ?? []
    }

    public static func encodeAnnotations(_ items: [URLCitation]?) -> Data? {
        URLCitation.encode(items)
    }

    public static func encodeToolCalls(_ items: [ToolCallInfo]?) -> Data? {
        ToolCallInfo.encode(items)
    }

    public static func encodeFileAttachments(_ items: [FileAttachment]?) -> Data? {
        FileAttachment.encode(items)
    }

    public static func encodeFilePathAnnotations(_ items: [FilePathAnnotation]?) -> Data? {
        FilePathAnnotation.encode(items)
    }

    public static func setAnnotations(_ items: [URLCitation], on message: Message) {
        message.annotationsData = encodeAnnotations(items.isEmpty ? nil : items)
    }

    public static func setToolCalls(_ items: [ToolCallInfo], on message: Message) {
        message.toolCallsData = encodeToolCalls(items.isEmpty ? nil : items)
    }

    public static func setFileAttachments(_ items: [FileAttachment], on message: Message) {
        message.fileAttachmentsData = encodeFileAttachments(items.isEmpty ? nil : items)
    }

    public static func setFilePathAnnotations(_ items: [FilePathAnnotation], on message: Message) {
        message.filePathAnnotationsData = encodeFilePathAnnotations(items.isEmpty ? nil : items)
    }

    public static func renderDigest(for message: Message) -> String {
        renderDigest(
            annotations: annotations(from: message.annotationsData),
            toolCalls: toolCalls(from: message.toolCallsData),
            fileAttachments: fileAttachments(from: message.fileAttachmentsData),
            filePathAnnotations: filePathAnnotations(from: message.filePathAnnotationsData)
        )
    }

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
