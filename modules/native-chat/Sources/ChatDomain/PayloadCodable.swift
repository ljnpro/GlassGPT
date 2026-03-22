import Foundation

/// Types conforming to `PayloadCodable` gain static `encode(_:)` and `decode(_:)`
/// helpers that round-trip optional arrays through `PayloadJSONCoding`.
package protocol PayloadCodable: Codable, Sendable {}

package extension PayloadCodable {
    static func codingFailureMessage(
        operation: String,
        error: some Error
    ) -> String {
        "Payload \(operation) failed for \(String(describing: Self.self)): \(error.localizedDescription)"
    }

    static func encodeOrThrow(_ items: [Self]?) throws(EncodingError) -> Data? {
        guard let items, !items.isEmpty else { return nil }
        return try PayloadJSONCoding.encode(items)
    }

    static func decodeOrThrow(_ data: Data?) throws(DecodingError) -> [Self]? {
        guard let data else { return nil }
        return try PayloadJSONCoding.decode([Self].self, from: data)
    }

    /// Encodes an optional array of items to JSON data, returning `nil` for empty or nil input.
    /// - Parameter items: The optional array to encode.
    /// - Returns: The encoded JSON data, or `nil` if the array is nil, empty, or encoding fails.
    static func encode(_ items: [Self]?) -> Data? {
        do {
            return try encodeOrThrow(items)
        } catch {
            NSLog("%@", codingFailureMessage(operation: "encode", error: error))
            return nil
        }
    }

    /// Decodes an optional array of items from JSON data, returning `nil` for nil input or on failure.
    /// - Parameter data: The JSON data to decode, or `nil`.
    /// - Returns: The decoded array, or `nil` if data is nil or decoding fails.
    static func decode(_ data: Data?) -> [Self]? {
        do {
            return try decodeOrThrow(data)
        } catch {
            NSLog("%@", codingFailureMessage(operation: "decode", error: error))
            return nil
        }
    }
}
