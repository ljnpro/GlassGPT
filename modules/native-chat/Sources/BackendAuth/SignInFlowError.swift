import Foundation

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

extension SignInFlowError {
    public var stageLabel: String {
        switch self {
        case .appleAuthorization:
            "apple-auth"
        case .backendAuthentication:
            "backend-auth"
        }
    }

    public var underlyingError: Error {
        switch self {
        case let .appleAuthorization(underlying), let .backendAuthentication(underlying):
            underlying
        }
    }
}
