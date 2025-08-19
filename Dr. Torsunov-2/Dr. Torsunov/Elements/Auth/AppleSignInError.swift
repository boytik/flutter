import AuthenticationServices
import Foundation

enum AppleSignInError: Error {
    case noCredential, noIdentityToken, encodingFailed
}

final class AppleSignIn: NSObject {
    private var continuation: CheckedContinuation<String, Error>?

    func start() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            self.continuation = continuation
            let req = ASAuthorizationAppleIDProvider().createRequest()
            req.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [req])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

extension AppleSignIn: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AppleSignInError.noCredential); continuation = nil; return
        }
        guard let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8) else {
            continuation?.resume(throwing: AppleSignInError.noIdentityToken); continuation = nil; return
        }
        continuation?.resume(returning: token)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

extension AppleSignIn: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}

