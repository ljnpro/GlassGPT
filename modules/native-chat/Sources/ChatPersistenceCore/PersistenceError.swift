import Foundation

/// Errors originating from the persistence layer.
public enum PersistenceError: Error, Sendable {
    /// The Keychain operation failed with the given OS status.
    case keychainFailure(OSStatus)
    /// The SwiftData migration could not complete.
    case migrationFailure(underlying: any Error)
    /// The model container is unavailable.
    case storeUnavailable
}
