import AuthenticationServices
import BackendAuth
import Foundation
import UIKit

@MainActor
package final class AppleSignInCoordinator: NSObject {
    private var continuation: CheckedContinuation<AppleSignInPayload, Error>?
    private var resolvedPresentationAnchor: ASPresentationAnchor!

    func signIn() async throws -> AppleSignInPayload {
        guard let presentationAnchor = resolvePresentationAnchor() else {
            throw AppleSignInCoordinatorError.missingPresentationAnchor
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            resolvedPresentationAnchor = presentationAnchor

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func finish(with result: Result<AppleSignInPayload, Error>) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        resolvedPresentationAnchor = nil
        continuation.resume(with: result)
    }

    private func resolvePresentationAnchor() -> ASPresentationAnchor? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            return keyWindow
        }

        if let firstWindow = scenes.first?.windows.first {
            return firstWindow
        }

        if let fallbackScene = scenes.first {
            return ASPresentationAnchor(windowScene: fallbackScene)
        }

        return nil
    }
}

private enum AppleSignInCoordinatorError: LocalizedError {
    case missingPresentationAnchor

    var errorDescription: String? {
        switch self {
        case .missingPresentationAnchor:
            "A presentation window is required to continue Sign in with Apple."
        }
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    /// Translates a successful Apple authorization into the backend auth payload used by Beta 5.0.
    package func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(with: .failure(CocoaError(.coderInvalidValue)))
            return
        }

        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8),
              !identityToken.isEmpty else {
            finish(with: .failure(CocoaError(.coderInvalidValue)))
            return
        }

        let authorizationCode = credential.authorizationCode.flatMap {
            String(data: $0, encoding: .utf8)
        }
        finish(
            with: .success(
                AppleSignInPayload(
                    userIdentifier: credential.user,
                    identityToken: identityToken,
                    authorizationCode: authorizationCode,
                    email: credential.email,
                    givenName: credential.fullName?.givenName,
                    familyName: credential.fullName?.familyName
                )
            )
        )
    }

    /// Finishes the in-flight sign-in attempt with the received Apple authorization error.
    package func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finish(with: .failure(error))
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    /// Returns the resolved presentation anchor for the active Apple sign-in flow.
    package func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        resolvedPresentationAnchor
    }
}
