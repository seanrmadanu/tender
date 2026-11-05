import AuthenticationServices
import UIKit

@MainActor
final class BankAuthenticationSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<Void, Error>?
    func open(_ hosted: HostedBankSession) async throws {
        guard hosted.presentation == "inApp", let url = hosted.safeURL else { throw BankError.message("Secure bank login is unavailable. Please try again later.") }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "tender") { [weak self] callback, error in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                            self.finish(.failure(CancellationError()))
                        } else if let error { self.finish(.failure(error)) }
                        else if let callback, Self.matches(callback, sessionID: hosted.id) { self.finish(.success(())) }
                        else { self.finish(.failure(BankError.message("Bank login could not return securely. Please try again."))) }
                    }
                }
                self.session = session
                session.presentationContextProvider = self
                if !session.start() { finish(.failure(BankError.message("Bank login could not open. Please try again."))) }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }
    static func matches(_ url: URL, sessionID: String) -> Bool {
        guard url.scheme == "tender", url.host == "bank-link-complete", url.user == nil, url.password == nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.queryItems?.filter { $0.name == "session" }.map(\.value) == [sessionID]
    }
    func cancel() { session?.cancel(); finish(.failure(CancellationError())) }
    private func finish(_ result: Result<Void, Error>) {
        let pending = continuation; continuation = nil; session = nil
        pending?.resume(with: result)
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
