import Foundation

/// Namespace providing JSON encoding and decoding helpers for the transport layer.
public enum JSONCoding {
    /// Encodes the given value to JSON data.
    /// - Parameter value: The value to encode.
    /// - Returns: The JSON-encoded data.
    /// - Throws: ``OpenAIServiceError`` if the value cannot be serialized.
    public static func encode(_ value: some Encodable) throws(OpenAIServiceError) -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw .requestFailed("JSON encoding failed: \(error.localizedDescription)")
        }
    }

    /// Decodes a value of the specified type from JSON data.
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - data: The JSON data to decode from.
    /// - Returns: The decoded value.
    /// - Throws: ``OpenAIServiceError`` if the data is invalid.
    public static func decode<T: Decodable>(_: T.Type, from data: Data) throws(OpenAIServiceError) -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw .requestFailed("JSON decoding failed: \(error.localizedDescription)")
        }
    }
}
