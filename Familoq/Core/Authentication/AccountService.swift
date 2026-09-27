import Foundation
import AuthenticationServices
import CryptoKit
import FamiloqCore

/// What the app needs from the invitation service (stubbed in tests).
protocol InvitationServicing {
    func redeem(code: String, identityToken: String, nonce: String) async throws -> InvitationServiceClient.Session
    func restore(identityToken: String, nonce: String) async throws -> InvitationServiceClient.Session
    func refresh(token: String) async throws -> InvitationServiceClient.Session
    func requestInvitation(name: String, contact: String, message: String) async throws
}

extension InvitationServiceClient: InvitationServicing {}

/// Result of a successful Sign in with Apple.
struct AppleCredential: Equatable {
    var userID: String
    var identityToken: String
    var rawNonce: String
    var displayName: String?
}

/// Level 1 access: is this person allowed to use Familoq?
///
///   no stored account  -> onboarding (invitation code / request / restore)
///   stored account     -> app (works offline); re-checked with the service at
///                         most once a day - a revoked account is signed out.
@MainActor
final class AccountService: ObservableObject {
    enum State: Equatable {
        case checking
        case needsInvitation
        case active(StoredAccount)
    }

    @Published private(set) var state: State = .checking
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private let service: InvitationServicing
    private let storage: AccountStorage
    private let now: () -> Date
    private let checkInterval: TimeInterval = 24 * 3600

    init(service: InvitationServicing, storage: AccountStorage, now: @escaping () -> Date = { Date() }) {
        self.service = service
        self.storage = storage
        self.now = now
    }

    /// Production wiring: URL from Info.plist (FQ_INVITE_SERVICE_URL), Keychain storage.
    static func live() -> AccountService {
        let urlString = Bundle.main.object(forInfoDictionaryKey: "FQInvitationServiceURL") as? String ?? ""
        let url = URL(string: urlString) ?? URL(string: "https://invalid.invalid")!
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demoAccount") {
            // CI screenshots / simulator demos only - never compiled into release builds.
            let demo = StoredAccount(appleUserID: "demo", displayName: "Demo", sessionToken: "demo",
                                     sessionExpiresAt: .distantFuture, activatedAt: Date(), lastCheckedAt: .distantFuture)
            return AccountService(service: InvitationServiceClient(baseURL: url), storage: InMemoryAccountStorage(demo))
        }
        #endif
        return AccountService(service: InvitationServiceClient(baseURL: url), storage: KeychainAccountStorage())
    }

    var account: StoredAccount? {
        if case .active(let account) = state { return account }
        return nil
    }

    var isActive: Bool { account != nil }

    func load() {
        if let stored = storage.load() {
            state = .active(stored)
        } else {
            state = .needsInvitation
        }
    }

    // MARK: Onboarding

    /// Enter an App Invitation code + Sign in with Apple.
    @discardableResult
    func redeem(code: String, credential: AppleCredential) async -> Bool {
        guard InvitationCode.isWellFormed(code) else {
            errorMessage = InvitationServiceClient.ServiceError.invalidCode.message
            return false
        }
        return await run {
            try await self.service.redeem(code: code, identityToken: credential.identityToken, nonce: credential.rawNonce)
        } store: { session in
            self.makeAccount(from: session, credential: credential)
        }
    }

    /// Reinstall / new device: the same Apple ID signs in again, no code needed.
    @discardableResult
    func restore(credential: AppleCredential) async -> Bool {
        await run {
            try await self.service.restore(identityToken: credential.identityToken, nonce: credential.rawNonce)
        } store: { session in
            self.makeAccount(from: session, credential: credential)
        }
    }

    @discardableResult
    func requestInvitation(name: String, contact: String, message: String) async -> Bool {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await service.requestInvitation(name: name, contact: contact, message: message)
            return true
        } catch {
            errorMessage = (error as? InvitationServiceClient.ServiceError)?.message ?? error.localizedDescription
            return false
        }
    }

    // MARK: Ongoing

    /// Re-validates the session at most once a day. Offline -> keeps working.
    func refreshIfDue(force: Bool = false) async {
        guard var account = account else { return }
        guard force || now().timeIntervalSince(account.lastCheckedAt) >= checkInterval else { return }
        do {
            let session = try await service.refresh(token: account.sessionToken)
            account.sessionToken = session.token
            account.sessionExpiresAt = Date(timeIntervalSince1970: session.expiresAt)
            account.lastCheckedAt = now()
            try? storage.save(account)
            state = .active(account)
        } catch InvitationServiceClient.ServiceError.accountRevoked {
            signOut()
            errorMessage = InvitationServiceClient.ServiceError.accountRevoked.message
        } catch {
            // Offline or temporary server problem: stay signed in (offline-first).
        }
    }

    /// Called when Apple reports the Apple ID link was revoked in Settings.
    func signOut() {
        storage.delete()
        state = .needsInvitation
    }

    /// Checks with Apple whether the user removed Familoq from "Sign in with Apple".
    func verifyAppleCredentialState() async {
        guard let account, account.appleUserID != "demo" else { return }
        let provider = ASAuthorizationAppleIDProvider()
        let credentialState: ASAuthorizationAppleIDProvider.CredentialState = await withCheckedContinuation { continuation in
            provider.getCredentialState(forUserID: account.appleUserID) { state, _ in
                continuation.resume(returning: state)
            }
        }
        if credentialState == .revoked {
            signOut()
        }
    }

    // MARK: Helpers

    private func makeAccount(from session: InvitationServiceClient.Session, credential: AppleCredential) -> StoredAccount {
        StoredAccount(
            appleUserID: credential.userID,
            displayName: credential.displayName ?? account?.displayName,
            sessionToken: session.token,
            sessionExpiresAt: Date(timeIntervalSince1970: session.expiresAt),
            activatedAt: now(),
            lastCheckedAt: now()
        )
    }

    private func run(_ call: @escaping () async throws -> InvitationServiceClient.Session,
                     store: @escaping (InvitationServiceClient.Session) -> StoredAccount) async -> Bool {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await call()
            let account = store(session)
            try storage.save(account)
            state = .active(account)
            return true
        } catch let error as InvitationServiceClient.ServiceError {
            errorMessage = error.message
        } catch {
            errorMessage = "Could not save your sign-in on this iPhone (\(error.localizedDescription))."
        }
        return false
    }
}

/// Helpers for "Sign in with Apple" with a nonce (prevents replayed tokens).
enum AppleSignIn {
    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset[Int(generator.next() % UInt64(charset.count))] })
    }

    /// SHA-256 as lowercase hex - this is what goes into the Apple request and
    /// what the server compares against the token's nonce claim.
    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func credential(from authorization: ASAuthorization, rawNonce: String) -> AppleCredential? {
        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = apple.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else { return nil }
        let name = [apple.fullName?.givenName, apple.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        return AppleCredential(userID: apple.user, identityToken: token, rawNonce: rawNonce, displayName: name.isEmpty ? nil : name)
    }
}
