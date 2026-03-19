import Foundation

/// Namespace providing JSON encoding and decoding helpers for domain payloads.
package enum PayloadJSONCoding {
    /// Encodes the given value to JSON data.
    /// - Parameter value: The value to encode.
    /// - Returns: The JSON-encoded data.
    /// - Throws: An encoding error if the value cannot be serialized.
    package static func encode(_ value: some Encodable) throws(EncodingError) -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch let error as EncodingError {
            throw error
        } catch {
            throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: error.localizedDescription))
        }
    }

    /// Decodes a value of the specified type from JSON data.
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - data: The JSON data to decode from.
    /// - Returns: The decoded value.
    /// - Throws: A decoding error if the data is invalid.
    package static func decode<T: Decodable>(_: T.Type, from data: Data) throws(DecodingError) -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as DecodingError {
            throw error
        } catch {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: error.localizedDescription))
        }
    }
}
