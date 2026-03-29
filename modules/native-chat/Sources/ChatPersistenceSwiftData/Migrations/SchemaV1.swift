import Foundation
import SwiftData

/// Frozen snapshot of the initial schema (5.0.0–5.1.3).
/// New migrations should add a SchemaV2 and define a MigrationStage.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        [Conversation.self, Message.self]
    }
}
