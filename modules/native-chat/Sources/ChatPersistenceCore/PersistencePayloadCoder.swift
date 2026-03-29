import Foundation

/// Shared JSON payload encoder/decoder used by persistence entities.
public enum PersistencePayloadCoder {
    /// Decodes a typed payload from raw persisted data, logging failures through the
    /// standard persistence logger.
    public static func decode<Payload: Decodable>(
        _: Payload.Type,
        from data: Data?,
        owner: String
    ) -> Payload? {
        guard let data else {
            return nil
        }

        do {
            return try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            Loggers.persistence.error(
                "\(owner) payload decode failed for \(String(describing: Payload.self)): \(error.localizedDescription)"
            )
            return nil
        }
    }

    /// Encodes a typed payload for persistence, logging failures through the
    /// standard persistence logger.
    public static func encode<Payload: Encodable>(
        _ value: Payload?,
        owner: String
    ) -> Data? {
        guard let value else {
            return nil
        }

        do {
            return try JSONEncoder().encode(value)
        } catch {
            Loggers.persistence.error(
                "\(owner) payload encode failed for \(String(describing: Payload.self)): \(error.localizedDescription)"
            )
            return nil
        }
    }
}
