import Foundation
import SwiftData

/// Schema migration plan for the chat persistence layer.
/// V1 corresponds to the initial schema shipped with 5.0.0 through 5.1.3.
public enum ChatSchemaMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
