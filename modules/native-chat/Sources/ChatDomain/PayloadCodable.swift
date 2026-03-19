import Foundation

/// Types conforming to `PayloadCodable` gain static `encode(_:)` and `decode(_:)`
/// helpers that round-trip optional arrays through `PayloadJSONCoding`.
package protocol PayloadCodable: Codable, Sendable {}

extension PayloadCodable {
    /// Encodes an optional array of items to JSON data, returning `nil` for empty or nil input.
    /// - Parameter items: The optional array to encode.
    /// - Returns: The encoded JSON data, or `nil` if the array is nil, empty, or encoding fails.
    package static func encode(_ items: [Self]?) -> Data? {
        guard let items, !items.isEmpty else { return nil }
        do {
            return try PayloadJSONCoding.encode(items)
        } catch {
            return nil
        }
    }

    /// Decodes an optional array of items from JSON data, returning `nil` for nil input or on failure.
    /// - Parameter data: The JSON data to decode, or `nil`.
    /// - Returns: The decoded array, or `nil` if data is nil or decoding fails.
    package static func decode(_ data: Data?) -> [Self]? {
        guard let data else { return nil }
        do {
            return try PayloadJSONCoding.decode([Self].self, from: data)
        } catch {
            return nil
        }
    }
}
