import Foundation
import FamiloqCore

/// Level 1 access: may this iCloud account use Familoq?
///
///   not activated      -> onboarding (invitation code / request / about)
///   activated          -> app; works offline; re-checked at most once a day
///   administrator      -> activated automatically, sees the Admin screen
///
/// Reinstall or new iPhone with the same iCloud account restores access
/// automatically (the redemption belongs to that iCloud account).
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

    let backend: AccessBackend
    private let storage: AccountStorage
    private let now: () -> Date
    private let checkInterval: TimeInterval = 24 * 3600

    init(backend: AccessBackend, storage: AccountStorage, now: @escaping () -> Date = { Date() }) {
        self.backend = backend
        self.storage = storage
        self.now = now
    }

    static func live() -> AccountService {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demoAccount") {
            // CI screenshots / simulator demos only - never in release builds.
            let demo = StoredAccount(userRecordName: "demo", isAdmin: false, activatedAt: Date(), lastCheckedAt: .distantFuture)
            return AccountService(backend: CloudKitAccessBackend.live(), storage: InMemoryAccountStorage(demo))
        }
        #endif
        return AccountService(backend: CloudKitAccessBackend.live(), storage: KeychainAccountStorage())
    }

    var account: StoredAccount? {
        if case .active(let account) = state { return account }
        return nil
    }

    var isActive: Bool { account != nil }
    var isAdmin: Bool { account?.isAdmin == true }

    /// Loads the stored activation; if there is none, silently tries to
    /// restore it from iCloud (reinstall / new iPhone / administrator).
    func load() async {
        if let stored = storage.load() {
            state = .active(stored)
            return
        }
        state = .needsInvitation
        _ = await restore(silently: true)
    }

    // MARK: Onboarding

    /// Redeem an App Invitation for the signed-in iCloud account.
    @discardableResult
    func redeem(code: String) async -> Bool {
        errorMessage = nil
        guard InvitationCode.isWellFormed(code) else {
            errorMessage = AccessError.invalidCode.localizedDescription
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let user = try await backend.currentUserRecordName()
            if await backend.isAdministrator() {
                try activate(user: user, isAdmin: true)
                return true
            }
            let hash = InvitationHashing.codeHash(code)
            switch try await backend.invitationStatus(codeHash: hash, now: now()) {
            case .notFound: throw AccessError.invitationNotFound
            case .expired: throw AccessError.expired
            case .revoked: throw AccessError.revoked
            case .active: break
            }
            switch try await backend.redeem(codeHash: hash, userRecordName: user) {
            case .redeemed, .alreadyMine: break
            case .usedBySomeoneElse: throw AccessError.used
            }
            if try await backend.isRevoked(userRecordName: user) { throw AccessError.accountRevoked }
            try activate(user: user, isAdmin: false)
            return true
        } catch {
            errorMessage = (error as? AccessError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }

    /// "Already invited?" - finds an earlier redemption of this iCloud account.
    @discardableResult
    func restore(silently: Bool = false) async -> Bool {
        if !silently {
            errorMessage = nil
            isWorking = true
        }
        defer { if !silently { isWorking = false } }
        do {
            let user = try await backend.currentUserRecordName()
            if await backend.isAdministrator() {
                try activate(user: user, isAdmin: true)
                return true
            }
            guard try await backend.hasRedemption(userRecordName: user) else { throw AccessError.notActivated }
            if try await backend.isRevoked(userRecordName: user) { throw AccessError.accountRevoked }
            try activate(user: user, isAdmin: false)
            return true
        } catch {
            if !silently {
                errorMessage = (error as? AccessError)?.localizedDescription ?? error.localizedDescription
            }
            return false
        }
    }

    @discardableResult
    func requestInvitation(name: String, contact: String, message: String) async -> Bool {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await backend.currentUserRecordName()
            try await backend.submitRequest(name: name, contact: contact, message: message)
            return true
        } catch {
            errorMessage = (error as? AccessError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: Ongoing

    /// At most once a day: is this account still allowed? Offline -> keep working.
    func refreshIfDue(force: Bool = false) async {
        guard var account = account, account.userRecordName != "demo" else { return }
        guard force || now().timeIntervalSince(account.lastCheckedAt) >= checkInterval else { return }
        do {
            let user = try await backend.currentUserRecordName()
            // Another iCloud account on this iPhone -> needs its own invitation.
            guard user == account.userRecordName else {
                signOut()
                return
            }
            if try await backend.isRevoked(userRecordName: user) {
                signOut()
                errorMessage = AccessError.accountRevoked.localizedDescription
                return
            }
            account.isAdmin = await backend.isAdministrator()
            account.lastCheckedAt = now()
            try? storage.save(account)
            state = .active(account)
        } catch AccessError.noICloudAccount {
            signOut()
        } catch {
            // Offline or temporary iCloud problem: stay signed in (offline-first).
        }
    }

    func signOut() {
        storage.delete()
        state = .needsInvitation
    }

    private func activate(user: String, isAdmin: Bool) throws {
        let account = StoredAccount(userRecordName: user, isAdmin: isAdmin, activatedAt: now(), lastCheckedAt: now())
        try storage.save(account)
        state = .active(account)
    }
}
