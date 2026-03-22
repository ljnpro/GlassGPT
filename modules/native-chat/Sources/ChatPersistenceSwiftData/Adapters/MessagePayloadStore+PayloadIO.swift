import ChatDomain
import Foundation
import os

package extension MessagePayloadStore {
    static func payloadItems<T: PayloadCodable>(
        _: T.Type,
        from data: Data?,
        label: String,
        logFailure: Bool = true
    ) -> [T] {
        do {
            return try decodedPayloadItems(T.self, from: data, label: label, logFailure: logFailure)
        } catch {
            return []
        }
    }

    static func encodedPayloadData<T: PayloadCodable>(
        _ items: [T]?,
        label: String,
        logFailure: Bool = true
    ) throws(EncodingError) -> Data? {
        do {
            return try T.encodeOrThrow(items)
        } catch {
            if logFailure {
                logger.error("Failed to encode \(label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            throw error
        }
    }

    static func decodedPayloadItems<T: PayloadCodable>(
        _: T.Type,
        from data: Data?,
        label: String,
        logFailure: Bool = true
    ) throws(DecodingError) -> [T] {
        do {
            return try T.decodeOrThrow(data) ?? []
        } catch {
            if logFailure {
                logger.error("Failed to decode \(label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            throw error
        }
    }

    static func storedPayloadData(
        _ items: [some PayloadCodable],
        existingData: Data?,
        label: String,
        logFailure: Bool = true
    ) -> Data? {
        guard !items.isEmpty else {
            return nil
        }

        do {
            return try encodedPayloadData(items, label: label, logFailure: logFailure)
        } catch {
            return existingData
        }
    }

    internal static func setPayload(
        _ items: [some PayloadCodable],
        existingData: Data?,
        label: String,
        assign: (Data?) -> Void
    ) {
        assign(storedPayloadData(items, existingData: existingData, label: label))
    }
}
