import Foundation

/// Errors that can occur during the two-phase Apple-then-backend sign-in flow.
public enum SignInFlowError: Error, Sendable {
    case appleAuthorization(underlying: Error)
    case backendAuthentication(underlying: Error)
}

extension SignInFlowError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .appleAuthorization(underlying):
            "Apple authorization failed before backend sign-in. \(underlying.localizedDescription)"
        case let .backendAuthentication(underlying):
            "Backend sign-in failed after Apple authorization. \(underlying.localizedDescription)"
        }
    }
}

public extension SignInFlowError {
    var stageLabel: String {
        switch self {
        case .appleAuthorization:
            "apple-auth"
        case .backendAuthentication:
            "backend-auth"
        }
    }

    var underlyingError: Error {
        switch self {
        case let .appleAuthorization(underlying), let .backendAuthentication(underlying):
            underlying
        }
    }
}
