import ChatDomain
import CryptoKit
import Foundation
import os

/// Encodes, decodes, and applies structured message payloads (citations, tool calls,
/// file attachments, and file-path annotations) stored as binary blobs on ``Message``.
public enum MessagePayloadStore {
    private static let digestEncodingFailureSentinel = Data(#"{"payload_encoding_error":true}"#.utf8)
    package static let logger = Logger(subsystem: "GlassGPT", category: "persistence")

    /// Decodes URL citations from binary data.
    public static func annotations(from data: Data?) -> [URLCitation] {
        payloadItems(URLCitation.self, from: data, label: "annotations")
    }

    /// Decodes tool call metadata from binary data.
    public static func toolCalls(from data: Data?) -> [ToolCallInfo] {
        payloadItems(ToolCallInfo.self, from: data, label: "tool calls")
    }

    /// Decodes file attachments from binary data.
    public static func fileAttachments(from data: Data?) -> [FileAttachment] {
        payloadItems(FileAttachment.self, from: data, label: "file attachments")
    }

    /// Decodes file-path annotations from binary data.
    public static func filePathAnnotations(from data: Data?) -> [FilePathAnnotation] {
        payloadItems(FilePathAnnotation.self, from: data, label: "file path annotations")
    }

    /// Encodes URL citations to binary data, returning `nil` for empty or nil input.
    public static func encodeAnnotations(_ items: [URLCitation]?) -> Data? {
        do {
            return try encodedPayloadData(items, label: "annotations")
        } catch {
            return nil
        }
    }

    /// Encodes tool call metadata to binary data.
    public static func encodeToolCalls(_ items: [ToolCallInfo]?) -> Data? {
        do {
            return try encodedPayloadData(items, label: "tool calls")
        } catch {
            return nil
        }
    }

    /// Encodes file attachments to binary data.
    public static func encodeFileAttachments(_ items: [FileAttachment]?) -> Data? {
        do {
            return try encodedPayloadData(items, label: "file attachments")
        } catch {
            return nil
        }
    }

    /// Encodes file-path annotations to binary data.
    public static func encodeFilePathAnnotations(_ items: [FilePathAnnotation]?) -> Data? {
        do {
            return try encodedPayloadData(items, label: "file path annotations")
        } catch {
            return nil
        }
    }

    /// Writes URL citations to the given message's `annotationsData` blob.
    public static func setAnnotations(_ items: [URLCitation], on message: Message) {
        setPayload(items, existingData: message.annotationsData, label: "annotations") {
            message.annotationsData = $0
        }
    }

    /// Writes tool call metadata to the given message's `toolCallsData` blob.
    public static func setToolCalls(_ items: [ToolCallInfo], on message: Message) {
        setPayload(items, existingData: message.toolCallsData, label: "tool calls") {
            message.toolCallsData = $0
        }
    }

    /// Writes file attachments to the given message's `fileAttachmentsData` blob.
    public static func setFileAttachments(_ items: [FileAttachment], on message: Message) {
        setPayload(items, existingData: message.fileAttachmentsData, label: "file attachments") {
            message.fileAttachmentsData = $0
        }
    }

    /// Writes file-path annotations to the given message's `filePathAnnotationsData` blob.
    public static func setFilePathAnnotations(_ items: [FilePathAnnotation], on message: Message) {
        setPayload(items, existingData: message.filePathAnnotationsData, label: "file path annotations") {
            message.filePathAnnotationsData = $0
        }
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

    package static func canonicalData(
        for value: some Encodable,
        logFailure: Bool = true
    ) -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(value)
        } catch {
            if logFailure {
                logger.error("Failed to encode payload digest component: \(error.localizedDescription, privacy: .public)")
            }
            return digestEncodingFailureSentinel
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
