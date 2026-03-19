import Foundation

/// Namespace providing JSON encoding and decoding helpers for the transport layer.
public enum JSONCoding {
    /// Encodes the given value to JSON data.
    /// - Parameter value: The value to encode.
    /// - Returns: The JSON-encoded data.
    /// - Throws: An encoding error if the value cannot be serialized.
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    /// Decodes a value of the specified type from JSON data.
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - data: The JSON data to decode from.
    /// - Returns: The decoded value.
    /// - Throws: A decoding error if the data is invalid.
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }
}
